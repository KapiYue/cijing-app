-- 对齐「今日学习完成」的定义（2026-08-17）
--
-- 原状态：completed 由 apply_review 与 mark_reading_complete 各自按
--   `reading_count > 0 and practice_count >= 5`
-- 就地判定。这个 5 是只存在于 SQL 里的魔法数字，客户端无从得知，于是
-- 练习总结页打出「今日学习完成！」时服务端可能仍是 false，首页继续显示
-- 「开启今日学习」。1.0 正式版首日真机试用即复现。
--
-- 新定义：**走到练习总结页就算完成**，由客户端显式调用
-- complete_daily_session() 置位，服务端不再自行推断。两处 upsert 只负责
-- 累计计数，不再碰 completed。

-- 1. apply_review：daily_activity 的 upsert 去掉 completed 推断
create or replace function public.apply_review(
  p_word_id uuid,
  p_quality integer,
  p_exercise_type text default 'self_rating',
  p_response_time_ms integer default null,
  p_answer text default null,
  p_expected_answer text default null
)
returns public.words
language plpgsql
security invoker
set search_path = public
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
    user_id, word_id, quality, exercise_type, response_time_ms, answer, expected_answer
  ) values (
    auth.uid(), p_word_id, p_quality, p_exercise_type, p_response_time_ms, p_answer, p_expected_answer
  );

  insert into public.daily_activity (user_id, activity_date, reviewed_count, practice_count)
  values (auth.uid(), current_date, 1, case when p_exercise_type = 'self_rating' then 0 else 1 end)
  on conflict (user_id, activity_date) do update set
    reviewed_count = daily_activity.reviewed_count + 1,
    practice_count = daily_activity.practice_count + excluded.practice_count,
    updated_at = now();

  return v_word;
end;
$$;

-- 2. mark_reading_complete：同样只累计，不判定 completed
create or replace function public.mark_reading_complete(p_reading_id uuid, p_minutes integer default 5)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_completed_at timestamptz;
begin
  select completed_at into v_completed_at from public.reading_sessions
  where id = p_reading_id and user_id = auth.uid() for update;
  if not found then raise exception 'Reading not found'; end if;

  if v_completed_at is not null then return; end if;
  update public.reading_sessions set completed_at = now() where id = p_reading_id;

  insert into public.daily_activity (user_id, activity_date, reading_count, minutes)
  values (auth.uid(), current_date, 1, greatest(1, p_minutes))
  on conflict (user_id, activity_date) do update set
    reading_count = daily_activity.reading_count + 1,
    minutes = daily_activity.minutes + excluded.minutes,
    updated_at = now();
end;
$$;

-- 3. 客户端走到练习总结页时调用，幂等；返回刷新后的今日计划，省一次往返
create or replace function public.complete_daily_session()
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
begin
  insert into public.daily_activity (user_id, activity_date, completed)
  values (auth.uid(), current_date, true)
  on conflict (user_id, activity_date) do update set
    completed = true,
    updated_at = now();

  return public.get_daily_plan();
end;
$$;

revoke execute on function public.complete_daily_session() from public, anon;
grant execute on function public.complete_daily_session() to authenticated;

-- 4. 生成次数：与"存了几篇短文"解耦
--
-- 原先命中缓存时既不产生新行、也不留任何痕迹，于是"今天生成了两次"在数据里
-- 完全看不出来。一度改成命中缓存就复制一行，但那会让"最近的短文"冒出同名条目
-- ——文章行数和生成次数本来就是两件事，硬塞进一张表才显得互相矛盾。
alter table public.daily_activity
  add column if not exists generation_count integer not null default 0;

create or replace function public.record_reading_generation()
returns void
language sql
security invoker
set search_path = public
as $$
  insert into public.daily_activity (user_id, activity_date, generation_count)
  values (auth.uid(), current_date, 1)
  on conflict (user_id, activity_date) do update set
    generation_count = daily_activity.generation_count + 1,
    updated_at = now();
$$;

revoke execute on function public.record_reading_generation() from public, anon;
grant execute on function public.record_reading_generation() to authenticated;

-- 5. get_daily_plan 带上今日生成次数（数据先就位，暂不在 UI 展示）
create or replace function public.get_daily_plan()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
with p as (
  select * from profiles where id = auth.uid()
), counts as (
  select
    count(*) filter (where status not in ('new', 'ignored') and due_at <= now()) as review_due,
    count(*) filter (where status = 'new') as new_available,
    count(*) filter (where status = 'weak') as weak_count,
    count(*) filter (where status <> 'ignored') as learned_count,
    count(*) filter (where status = 'mastered') as mastered_count
  from words where user_id = auth.uid()
), today as (
  select coalesce(reviewed_count, 0) as reviewed_count,
         coalesce(practice_count, 0) as practice_count,
         coalesce(reading_count, 0) as reading_count,
         coalesce(generation_count, 0) as generation_count,
         coalesce(completed, false) as completed
  from daily_activity where user_id = auth.uid() and activity_date = current_date
), streak as (
  select count(*) as days from (
    select activity_date,
      activity_date - (row_number() over (order by activity_date))::integer as grp
    from daily_activity
    where user_id = auth.uid() and (reviewed_count > 0 or reading_count > 0)
  ) s
  where grp = (
    select max(activity_date - rn::integer) from (
      select activity_date, row_number() over (order by activity_date) rn
      from daily_activity
      where user_id = auth.uid() and (reviewed_count > 0 or reading_count > 0)
    ) z
  )
)
select jsonb_build_object(
  'review_due', least(c.review_due, p.daily_review_goal),
  'new_suggested', least(c.new_available, p.daily_new_goal),
  'weak_count', c.weak_count,
  'learned_count', c.learned_count,
  'mastered_count', c.mastered_count,
  'streak_days', coalesce(s.days, 0),
  'reviewed_today', coalesce(t.reviewed_count, 0),
  'practice_today', coalesce(t.practice_count, 0),
  'reading_today', coalesce(t.reading_count, 0),
  'generation_today', coalesce(t.generation_count, 0),
  'completed_today', coalesce(t.completed, false),
  'daily_new_goal', p.daily_new_goal,
  'daily_review_goal', p.daily_review_goal
)
from p cross join counts c cross join streak s left join today t on true;
$$;
