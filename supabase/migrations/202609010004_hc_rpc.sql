-- 活词的 RPC。全部是「解释」层（§14.1 T7），词鲸不调用、不受影响。
--
-- 依赖：supabase/migrations/202609010002_review_idempotency.sql 必须**先**跑
--       （hc_apply_review 要用到带 p_client_event_id 的新签名）。

-- ─────────────────────────────────────────────────────────────
-- 今日队列。《执行方案》§6.1
--
--   今日队列 = 到期复习卡（按 due 升序）
--            + 新词（配额 = max(0, daily_goal − 到期数)）
--   新词优先级：capture 的词 > level_line 之上的底座词      ← P2 无词包，故只有两级
--   断更欠账：单日上限 = daily_goal × 1.5 = 30，不一次性倾泻
--
-- 「capture > 词包」这条优先级**必须在排序代码里体现，不是文案**（§6.1 的红字）。
-- 为什么不复用词鲸的 get_learning_targets：它按 weak → due → new → learning 排，
-- 不区分 capture 与底座，也没有欠账上限——那是词鲸的编排，不是活词的。
-- 两端「今日学什么」本来就不要求一致（T7 明确接受的代价）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.hc_get_study_queue(p_limit integer default 20)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
set timezone = 'Asia/Shanghai'
as $$
declare
  v_goal integer;
  v_cap integer;
  v_due_count integer;
  v_new_quota integer;
  v_result jsonb;
begin
  select coalesce(daily_goal, 20) into v_goal
  from public.hc_profiles where user_id = auth.uid();
  v_goal := coalesce(v_goal, 20);

  -- 断更欠账不一次性倾泻
  v_cap := least(greatest(1, p_limit), (v_goal * 1.5)::integer);

  select count(*) into v_due_count
  from public.words
  where user_id = auth.uid()
    and status not in ('new', 'ignored')
    and due_at <= now();

  v_new_quota := greatest(0, v_goal - v_due_count);

  with due as (
    select w.*, 0 as bucket, 0 as capture_rank, w.due_at as ord
    from public.words w
    where w.user_id = auth.uid()
      and w.status not in ('new', 'ignored')
      and w.due_at <= now()
    order by w.due_at asc
    limit v_cap
  ),
  fresh as (
    select w.*, 1 as bucket,
      -- capture 词（有原句或来源）排在底座词前面
      case when w.first_context is not null or w.first_source_url is not null then 0 else 1 end
        as capture_rank,
      w.created_at as ord
    from public.words w
    where w.user_id = auth.uid()
      and w.status = 'new'
    order by capture_rank asc, w.created_at asc
    limit v_new_quota
  ),
  merged as (
    select * from due
    union all
    select * from fresh
  ),
  -- ⚠️ LIMIT 必须跟在 ORDER BY 后面。裸 limit 一个 union all 的结果，
  -- 留下哪些行是不确定的 —— 到期词可能被新词挤掉，队列当场失序。
  ranked as (
    select * from merged
    order by bucket, capture_rank, ord
    limit v_cap
  )
  select coalesce(jsonb_agg(to_jsonb(m) - 'bucket' - 'capture_rank' - 'ord' || jsonb_build_object(
           'activated_at', s.activated_at,
           'is_capture', (m.first_context is not null or m.first_source_url is not null)
         ) order by m.bucket, m.capture_rank, m.ord), '[]'::jsonb)
    into v_result
  from ranked m
  left join public.hc_word_status s
    on s.user_id = m.user_id and s.word_id = m.id;

  return v_result;
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- 提交一次复习。**客户端只调这一个**，不直接调 apply_review。
--
-- 为什么包一层：§3.3 的 activated_at「一次写入永不改写」是跨三端的不变量，
-- 交给客户端判断迟早会有一端漏判。放在这里，事实与解释在**同一个事务**里落地。
-- ─────────────────────────────────────────────────────────────
create or replace function public.hc_apply_review(
  p_word_id uuid,
  p_quality integer,
  p_exercise_type text default 'self_rating',
  p_response_time_ms integer default null,
  p_client_event_id uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
set timezone = 'Asia/Shanghai'
as $$
declare
  v_word public.words;
  v_activated_at timestamptz;
  v_was_activated boolean;
begin
  select activated_at into v_activated_at
  from public.hc_word_status
  where user_id = auth.uid() and word_id = p_word_id;
  v_was_activated := v_activated_at is not null;

  v_word := public.apply_review(
    p_word_id, p_quality, p_exercise_type, p_response_time_ms, null, null, p_client_event_id
  );

  -- §3.1 判据：repetitions > 0 且 interval_days >= 21 时首次盖章。
  -- ⚠️ 阈值 21 写死在这里是有意的——它只能升不能降，且改阈值时已落库的不重算（§3.2）。
  if not v_was_activated and v_word.repetitions > 0 and v_word.interval_days >= 21 then
    insert into public.hc_word_status (user_id, word_id, activated_at)
    values (auth.uid(), p_word_id, now())
    on conflict (user_id, word_id) do nothing;

    select activated_at into v_activated_at
    from public.hc_word_status
    where user_id = auth.uid() and word_id = p_word_id;
  end if;

  return jsonb_build_object(
    'word', to_jsonb(v_word),
    'activated_at', v_activated_at,
    -- 首页「新激活 +N」与北极星都吃这个字段
    'newly_activated', (not v_was_activated and v_activated_at is not null)
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- 首页概览。§6.1 的「7 个词需要复习 / 13 个新词 / 连续 6 天 / 已经激活 83 个活词」
--
-- ⚠️ 「已经激活 N 个活词」只能来自 hc_word_status，**不能**用词鲸的 mastered_count
--    —— 那是词鲸自己的 status 枚举，与活词五态的 activated 不是一回事。
-- ─────────────────────────────────────────────────────────────
create or replace function public.hc_home_summary()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
set timezone = 'Asia/Shanghai'
as $$
declare
  v_plan jsonb;
  v_goal integer;
  v_activated integer;
  v_activated_week integer;
  v_due integer;
  v_new integer;
  v_total integer;
begin
  v_plan := public.get_daily_plan();

  select coalesce(daily_goal, 20) into v_goal
  from public.hc_profiles where user_id = auth.uid();
  v_goal := coalesce(v_goal, 20);

  select count(*) into v_activated
  from public.hc_word_status where user_id = auth.uid();

  -- 北极星：Weekly Activated Words（§8.1）
  select count(*) into v_activated_week
  from public.hc_word_status
  where user_id = auth.uid() and activated_at >= now() - interval '7 days';

  select
    count(*) filter (where status not in ('new', 'ignored') and due_at <= now()),
    count(*) filter (where status = 'new'),
    count(*) filter (where status <> 'ignored')
  into v_due, v_new, v_total
  from public.words where user_id = auth.uid();

  return jsonb_build_object(
    'due_count', v_due,
    'new_count', least(v_new, greatest(0, v_goal - v_due)),
    'new_available', v_new,
    'total_words', v_total,
    'daily_goal', v_goal,
    'streak_days', coalesce((v_plan ->> 'streak_days')::integer, 0),
    'reviewed_today', coalesce((v_plan ->> 'reviewed_today')::integer, 0),
    'activated_count', v_activated,
    'activated_this_week', v_activated_week
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- 埋点批量上报。§4.5：攒批 + 一轮学习结束时一次性 flush，**不单独发请求**。
-- ─────────────────────────────────────────────────────────────
create or replace function public.hc_track(p_events jsonb)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_count integer;
begin
  if jsonb_typeof(p_events) <> 'array' then
    raise exception 'p_events 必须是数组';
  end if;

  insert into public.hc_events (user_id, platform, name, props, client_ts, session_id)
  select
    auth.uid(),
    coalesce(e ->> 'platform', 'mp'),
    e ->> 'name',
    coalesce(e -> 'props', '{}'::jsonb),
    (e ->> 'client_ts')::timestamptz,
    e ->> 'session_id'
  from jsonb_array_elements(p_events) e
  where e ->> 'name' is not null;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.hc_get_study_queue(integer) from public, anon;
revoke execute on function public.hc_apply_review(uuid, integer, text, integer, uuid) from public, anon;
revoke execute on function public.hc_home_summary() from public, anon;
revoke execute on function public.hc_track(jsonb) from public, anon;

grant execute on function public.hc_get_study_queue(integer) to authenticated;
grant execute on function public.hc_apply_review(uuid, integer, text, integer, uuid) to authenticated;
grant execute on function public.hc_home_summary() to authenticated;
grant execute on function public.hc_track(jsonb) to authenticated;
