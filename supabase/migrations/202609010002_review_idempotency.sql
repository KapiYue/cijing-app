-- review_events 幂等键。改动源自活词《执行方案》§4.0 ①、§14.1 T1-c，落到词鲸这边。
--
-- ⚠️ 生产是 2026-09-01 在 SQL Editor **手工执行**的，且抢在 202609010001 之前，
--    因此那边的 apply_review 只剩 7 参数版。0001 的五条 ALTER 已于 2026-09-02 手工补跑，
--    两份的迁移历史同日用 `migration repair --status applied` 补记，现已与本地对齐。
--    经过见发布清单 12.5 节。全新库按编号顺序重放不受影响。
--
-- 为什么词鲸也需要它：小程序在通勤/地铁场景必须做离线写队列，补发时网络抖动会重放，
-- 同一次复习被算两遍，interval / ease 直接算错。现有 apply_review 没有任何幂等键。
--
-- 写这份时以为词鲸真实用户数为 0。实际是 8 个账号 / 88 条 review_events，但幂等键
-- 是纯增列（可空 + 部分唯一索引），历史行 client_event_id 为 null 不参与去重，
-- 所以「无回填、无向后兼容负担」的结论仍然成立。
--
-- 兼容性：新参数 p_client_event_id 带默认值，iOS（SupabaseAPI.swift）与 Chrome 扩展
-- 现有的按名传参调用**零改动**照常工作。

alter table public.review_events
  add column if not exists client_event_id uuid;

create unique index if not exists review_events_client_event_uidx
  on public.review_events (user_id, client_event_id)
  where client_event_id is not null;

-- 签名变了（多一个参数），必须先 drop 再建。旧签名的 grant 会一并消失，文件末尾补回。
drop function if exists public.apply_review(uuid, integer, text, integer, text, text);

create or replace function public.apply_review(
  p_word_id uuid,
  p_quality integer,
  p_exercise_type text default 'self_rating',
  p_response_time_ms integer default null,
  p_answer text default null,
  p_expected_answer text default null,
  p_client_event_id uuid default null
)
returns public.words
language plpgsql
security invoker
set search_path = public
-- 日界随北京时区（202609010001 的约定）。重建函数时必须一起带上，否则静默退回 UTC。
set timezone = 'Asia/Shanghai'
as $$
declare
  v_word public.words;
  v_interval integer;
  v_ease real;
  v_repetitions integer;
  v_status public.word_learning_status;
  v_strength real;
begin
  if p_quality < 0 or p_quality > 5 then raise exception 'quality must be 0...5'; end if;

  -- 幂等：这次复习已经记过了，直接把当前状态还回去，**不重算调度**。
  if p_client_event_id is not null and exists (
    select 1 from public.review_events
    where user_id = auth.uid() and client_event_id = p_client_event_id
  ) then
    select * into v_word from public.words where id = p_word_id and user_id = auth.uid();
    if not found then raise exception 'Word not found'; end if;
    return v_word;
  end if;

  select * into v_word from public.words
  where id = p_word_id and user_id = auth.uid() for update;
  if not found then raise exception 'Word not found'; end if;

  v_ease := greatest(1.3, least(3.5,
    v_word.ease_factor + (0.1 - (5 - p_quality) * (0.08 + (5 - p_quality) * 0.02))));

  if p_quality < 3 then
    v_repetitions := 0;
    v_interval := 1;
    v_status := 'weak';
    v_strength := greatest(0, v_word.strength - 0.18);
  else
    v_repetitions := v_word.repetitions + 1;
    v_interval := case
      when v_repetitions = 1 then 1
      when v_repetitions = 2 then 3
      else greatest(1, round(greatest(v_word.interval_days, 3) * v_ease *
        case when p_quality = 3 then 0.75 when p_quality = 5 then 1.2 else 1 end)::integer)
    end;
    v_strength := least(1, v_word.strength + (0.08 + p_quality * 0.025));
    v_status := case
      when v_strength >= 0.86 and v_interval >= 21 then 'mastered'
      when v_repetitions <= 1 then 'learning'
      else 'review'
    end;
  end if;

  update public.words set
    ease_factor = v_ease,
    interval_days = v_interval,
    repetitions = v_repetitions,
    lapses = lapses + case when p_quality < 3 then 1 else 0 end,
    error_count = error_count + case when p_quality < 3 then 1 else 0 end,
    strength = v_strength,
    status = v_status,
    due_at = now() + make_interval(days => v_interval),
    last_reviewed_at = now(),
    mastered_at = case when v_status = 'mastered' then coalesce(mastered_at, now()) else mastered_at end
  where id = p_word_id returning * into v_word;

  insert into public.review_events (
    user_id, word_id, quality, exercise_type, response_time_ms, answer, expected_answer,
    client_event_id
  ) values (
    auth.uid(), p_word_id, p_quality, p_exercise_type, p_response_time_ms, p_answer,
    p_expected_answer, p_client_event_id
  );

  insert into public.daily_activity (user_id, activity_date, reviewed_count, practice_count)
  values (auth.uid(), current_date, 1, case when p_exercise_type = 'self_rating' then 0 else 1 end)
  on conflict (user_id, activity_date) do update set
    reviewed_count = daily_activity.reviewed_count + 1,
    practice_count = daily_activity.practice_count + excluded.practice_count,
    -- 兼容期保留：与 202607200001 逐字一致，线上 1.0 行为零变化。
    completed = daily_activity.completed or (
      daily_activity.reading_count > 0 and daily_activity.practice_count + excluded.practice_count >= 5
    ),
    updated_at = now();

  return v_word;
end;
$$;

revoke execute on function
  public.apply_review(uuid, integer, text, integer, text, text, uuid) from public, anon;
grant execute on function
  public.apply_review(uuid, integer, text, integer, text, text, uuid) to authenticated;

-- 202609010001 末尾的断言只在那次迁移里跑过一次。这里重建了 apply_review，
-- 把「写 daily_activity 的函数必须挂时区」再机器化验一遍，防止漏挂静默退回 UTC。
do $$
declare
  v_bad text;
begin
  select string_agg(p.proname, ', ') into v_bad
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosrc like '%daily_activity%'
    and not exists (
      select 1 from unnest(coalesce(p.proconfig, '{}')) c where lower(c) like 'timezone=%'
    );
  if v_bad is not null then
    raise exception '这些函数写 daily_activity 却没挂 timezone GUC，日界会退回 UTC：%', v_bad;
  end if;
end;
$$;
