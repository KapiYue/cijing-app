-- 成就体系：分级成就线 + 解锁时刻留痕（2026-08-17）
--
-- 原状态：练习总结页的徽章是三行硬编码字符串（「初来乍到 / 铜章 / 完成第一篇
-- 个性化阅读」），没有任何条件判断——每次学完都弹、永远同一个，从第二次起
-- 就是假的。
--
-- 新模型（多邻国式）：几条成就线，每条按数值门槛分铜/银/金/铂金四级，同一枚
-- 徽章原地升级。等级本身**由现有数据推导**，不落库；落库的只有「哪一级在什么
-- 时候第一次解锁」，用来保证弹窗只在跨级那一刻出现一次。

-- 1. 解锁记录。track 是成就线标识，tier 是级别序号（1 = 铜，2 = 银，3 = 金，
--    4 = 铂金）。同一线同一级只可能解锁一次。
create table if not exists public.achievements (
  user_id uuid not null references auth.users(id) on delete cascade,
  track text not null,
  tier integer not null check (tier between 1 and 4),
  unlocked_at timestamptz not null default now(),
  primary key (user_id, track, tier)
);

alter table public.achievements enable row level security;

create policy "achievements_owner_all" on public.achievements for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update, delete on public.achievements to authenticated;

-- 2. 幂等地记录一次解锁。已解锁过则原样返回既有时间，调用方据此判断
--    「这次是不是新解锁」——避免同一级重复弹窗。
create or replace function public.unlock_achievement(p_track text, p_tier integer)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_existing timestamptz;
begin
  if p_tier < 1 or p_tier > 4 then raise exception 'tier must be 1...4'; end if;

  select unlocked_at into v_existing from public.achievements
  where user_id = auth.uid() and track = p_track and tier = p_tier;

  if found then
    return jsonb_build_object('track', p_track, 'tier', p_tier,
      'unlocked_at', v_existing, 'newly_unlocked', false);
  end if;

  insert into public.achievements (user_id, track, tier)
  values (auth.uid(), p_track, p_tier);

  return jsonb_build_object('track', p_track, 'tier', p_tier,
    'unlocked_at', now(), 'newly_unlocked', true);
end;
$$;

revoke execute on function public.unlock_achievement(text, integer) from public, anon;
grant execute on function public.unlock_achievement(text, integer) to authenticated;

-- 3. 连续天数改口径：只数「真正完成」的日子
--
-- 原来的 streak 按 `reviewed_count > 0 or reading_count > 0` 数连续段——答一道
-- 题就算一天。这与 202608170001 确立的完成定义（走到练习总结页 → completed）
-- 不是一回事，会出现「首页说连续 5 天、成就说 3 天」这类自相矛盾，和那份迁移
-- 修掉的是同一类问题。成就要挂在连续天数上，两边必须先对齐。
--
-- 新口径：streak 只数 completed = true 的日子，且必须连到今天或昨天为止
-- （昨天算「今天还来得及」，前天就断了）。
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
), completed_days as (
  select activity_date,
    activity_date - (row_number() over (order by activity_date))::integer as grp
  from daily_activity
  where user_id = auth.uid() and completed
), current_run as (
  select count(*) as days
  from completed_days
  where grp = (
    select grp from completed_days order by activity_date desc limit 1
  )
    and exists (
      select 1 from completed_days
      where activity_date >= current_date - 1
    )
), totals as (
  select count(*) as reading_total from reading_sessions
  where user_id = auth.uid() and completed_at is not null
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
  'reading_total', coalesce(r.reading_total, 0),
  'completed_today', coalesce(t.completed, false),
  'daily_new_goal', p.daily_new_goal,
  'daily_review_goal', p.daily_review_goal
)
from p
  cross join counts c
  cross join current_run s
  cross join totals r
  left join today t on true;
$$;
