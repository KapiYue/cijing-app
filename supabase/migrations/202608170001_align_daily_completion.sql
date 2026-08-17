-- 对齐「今日学习完成」的定义（2026-08-17）
--
-- 原状态：completed 由 apply_review 与 mark_reading_complete 各自按
--   `reading_count > 0 and practice_count >= 5`
-- 就地判定。这个 5 是只存在于 SQL 里的魔法数字，客户端无从得知，于是
-- 练习总结页打出「今日学习完成！」时服务端可能仍是 false，首页继续显示
-- 「开启今日学习」。1.0 正式版首日真机试用即复现。
--
-- 新定义：**走到练习总结页就算完成**，由客户端显式调用
-- complete_daily_session() 置位。
--
-- ⚠️ 本迁移为**向后兼容版（expand 阶段）**：旧的服务端推断规则原样保留，只做加法。
--
-- 为什么。初版把「新增 complete_daily_session()」和「删除旧推断」打包在一起，于是
-- 整批迁移被它绑死——线上 1.0 客户端不会调新 RPC，一旦旧推断被删，那些用户的
-- 「今日完成」将永远不再置位。这违反了本项目自己的迁移指南（supabase-migration-guide.md
-- 第 95 行：删除旧行为应等确认旧客户端退出使用后再做）。现在拆成两步：
--
--   expand（本迁移）  ：新增 RPC 与计数列，旧规则不动 —— 可先于客户端上线；
--   contract（1.0.1 上架后）：新增一份前向迁移删掉旧规则，那时才真正兑现
--                             「魔法数字 5 从代码库消失」。
--
-- 两条路径不冲突：旧规则与新 RPC **都只把 completed 置 true，从不置回 false**。
-- 代价是在 contract 之前，新客户端上「答满 5 题但没走到总结页」也会被算作完成——
-- 这正是 1.0 一直以来的行为，方向上也不是 11.1 抱怨的那一个（当时是「App 说完成、
-- 首页说没完成」，反过来则无人受损）。
--
-- 🔴 contract 那份迁移别忘了写，否则这个魔法数字会永远留下来。

-- 1. apply_review：只加计数列，completed 的旧推断**原样保留**
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
    -- 兼容期保留：与 202607200001 逐字一致，线上 1.0 行为零变化。
    -- contract 阶段（1.0.1 上架后）删掉这一行。
    completed = daily_activity.completed or (
      daily_activity.reading_count > 0 and daily_activity.practice_count + excluded.practice_count >= 5
    ),
    updated_at = now();

  return v_word;
end;
$$;

-- 2. mark_reading_complete：同样只加计数，旧推断原样保留
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
    -- 兼容期保留：与 202607200001 逐字一致。contract 阶段删掉这一行。
    completed = daily_activity.completed or daily_activity.practice_count >= 5,
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
