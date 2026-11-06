-- 收紧活词私有表写入：客户端只能通过受控 hc_* RPC 写 hc_profiles、hc_word_status、hc_events。
--
-- 共享事实 words / review_events / word_contexts / daily_activity 继续由词鲸现有 RPC 与 RLS 管理；
-- 本迁移不修改它们的权限，也不复制用户数据。所有函数保持 auth.uid() 为唯一用户主键。

-- hc_apply_review 是 hc_word_status 的唯一写入口。改为 definer 后仍以调用者 auth.uid() 读写词鲸事实，
-- 只对私有状态表获得必要的受控写权限；不接受 user_id 参数。
create or replace function public.hc_apply_review(
  p_word_id uuid,
  p_quality integer,
  p_exercise_type text default 'self_rating',
  p_response_time_ms integer default null,
  p_client_event_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
set timezone = 'Asia/Shanghai'
as $$
declare
  v_uid uuid := auth.uid();
  v_word public.words;
  v_activated_at timestamptz;
  v_was_activated boolean;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select activated_at into v_activated_at
  from public.hc_word_status
  where user_id = v_uid and word_id = p_word_id;
  v_was_activated := v_activated_at is not null;

  v_word := public.apply_review(
    p_word_id, p_quality, p_exercise_type, p_response_time_ms, null, null, p_client_event_id
  );

  if not v_was_activated and v_word.repetitions > 0 and v_word.interval_days >= 21 then
    insert into public.hc_word_status (user_id, word_id, activated_at)
    values (v_uid, p_word_id, now())
    on conflict (user_id, word_id) do nothing;

    select activated_at into v_activated_at
    from public.hc_word_status
    where user_id = v_uid and word_id = p_word_id;
  end if;

  return jsonb_build_object(
    'word', to_jsonb(v_word),
    'activated_at', v_activated_at,
    'newly_activated', (not v_was_activated and v_activated_at is not null)
  );
end;
$$;

-- hc_update_profile 只接受每日目标，不允许客户端直接写 level_line、scenes 或 onboarding 时间。
create or replace function public.hc_update_profile(p_daily_goal integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.hc_profiles;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if p_daily_goal is null or p_daily_goal not between 1 and 100 then
    raise exception 'daily_goal 必须在 1–100，收到 %', p_daily_goal;
  end if;

  insert into public.hc_profiles (user_id, daily_goal, updated_at)
  values (v_uid, p_daily_goal, now())
  on conflict (user_id) do update set
    daily_goal = excluded.daily_goal,
    updated_at = now()
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

-- 首启仍是唯一允许写 level_line / scenes / onboarding_done_at 的入口；其余逻辑与 0005 保持一致。
create or replace function public.hc_save_onboarding(
  p_scenes text[] default '{}',
  p_level_line integer default null,
  p_seed_terms text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
set timezone = 'Asia/Shanghai'
as $$
declare
  v_uid uuid := auth.uid();
  v_first_run boolean;
  v_done_at timestamptz;
  v_seeded integer := 0;
  v_ignored integer := 0;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if p_level_line is not null and p_level_line not between 1 and 6 then
    raise exception 'level_line 必须是 1–6 的频段序号，收到 %', p_level_line;
  end if;

  select onboarding_done_at into v_done_at from public.hc_profiles where user_id = v_uid;
  v_first_run := v_done_at is null;

  insert into public.hc_profiles (user_id, level_line, scenes, onboarding_done_at, updated_at)
  values (v_uid, p_level_line::smallint, coalesce(p_scenes, '{}'), now(), now())
  on conflict (user_id) do update set
    level_line = coalesce(excluded.level_line, hc_profiles.level_line),
    scenes = excluded.scenes,
    onboarding_done_at = coalesce(hc_profiles.onboarding_done_at, excluded.onboarding_done_at),
    updated_at = now()
  returning onboarding_done_at into v_done_at;

  if v_first_run then
    update public.words set status = 'ignored'
    where user_id = v_uid and status = 'new' and repetitions = 0 and last_reviewed_at is null
      and first_source_title = '词鲸新手词库';
    get diagnostics v_ignored = row_count;

    with seeds as (
      select lower(trim(t.term)) as norm, trim(t.term) as term, t.ord
      from unnest(coalesce(p_seed_terms, '{}')) with ordinality as t(term, ord)
      where nullif(trim(t.term), '') is not null
    ), deduped as (
      select distinct on (norm) norm, term, ord from seeds order by norm, ord
    ), ins as (
      insert into public.words (
        user_id, term, normalized_term, lemma, phonetic, primary_meaning, status, created_at
      )
      select v_uid, d.term, d.norm, d.norm, b.phonetic,
        coalesce(nullif(b.primary_meaning, ''), '待补充'), 'new',
        now() + make_interval(secs => d.ord::integer)
      from deduped d left join public.hc_base_words b on b.spelling = d.norm
      order by d.ord
      on conflict (user_id, normalized_term) do nothing
      returning 1
    ) select count(*) into v_seeded from ins;
  end if;

  return jsonb_build_object(
    'first_run', v_first_run,
    'level_line', p_level_line,
    'seeded_count', v_seeded,
    'ignored_starter_count', v_ignored,
    'onboarding_done_at', v_done_at
  );
end;
$$;

-- hc_track 保留批量事件接口，禁止客户端伪造 user_id 直接插表。
create or replace function public.hc_track(p_events jsonb)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(p_events) <> 'array' then
    raise exception 'p_events 必须是数组';
  end if;

  insert into public.hc_events (user_id, platform, name, props, client_ts, session_id)
  select v_uid, coalesce(e ->> 'platform', 'mp'), e ->> 'name',
    coalesce(e -> 'props', '{}'::jsonb), (e ->> 'client_ts')::timestamptz, e ->> 'session_id'
  from jsonb_array_elements(p_events) e
  where e ->> 'name' is not null;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke insert, update on public.hc_profiles from authenticated;
revoke insert on public.hc_word_status from authenticated;
revoke insert on public.hc_events from authenticated;

revoke execute on function public.hc_apply_review(uuid, integer, text, integer, uuid) from public, anon;
revoke execute on function public.hc_update_profile(integer) from public, anon;
revoke execute on function public.hc_save_onboarding(text[], integer, text[]) from public, anon;
revoke execute on function public.hc_track(jsonb) from public, anon;
grant execute on function public.hc_apply_review(uuid, integer, text, integer, uuid) to authenticated;
grant execute on function public.hc_update_profile(integer) to authenticated;
grant execute on function public.hc_save_onboarding(text[], integer, text[]) to authenticated;
grant execute on function public.hc_track(jsonb) to authenticated;
