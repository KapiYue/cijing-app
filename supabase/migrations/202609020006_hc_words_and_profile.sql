-- S6「我的生词」与 S8「我的」要用的两个 RPC。`design.md` §5.4 S6 / S8。
--
-- 依赖 `202609010003_hc_core_tables.sql`（hc_profiles / hc_word_status）。
--
-- 为什么列表也走 RPC 而不是裸 REST：
--   S6 的第三个筛选「已激活」的判据在 `hc_word_status`（附录 A：`activated_at` 非空，
--   **一次写入永不改写**），不在 `words` 上。用 REST 就得让客户端自己拼两张表 ——
--   要么依赖 PostgREST 的资源嵌入（跨版本行为不稳），要么拉两次再在端上 join。
--   而「已激活的词退回未激活」正是 §8.2 明令禁止的回退：`interval_days >= 21` 这个
--   便捷判据在 lapse 之后会变假，只有 `activated_at` 不会。判据只能有一处实现，放服务端。

-- ─────────────────────────────────────────────────────────────
-- 我的生词列表。三个筛选与 §5.4 S6 的三个 tab 一一对应。
--
--   recent     最近遇到 —— 按 created_at 倒序（「遇到」= 入库时间）
--   due        待复习   —— 已学过且到期，按 due_at 升序（最该先复习的排最前）
--   activated  已激活   —— hc_word_status 有行，按 activated_at 倒序
--
-- 'ignored' 一律排除：那是首启忽略掉的词鲸新手词（§11 ⑤），用户没选过它们。
-- ─────────────────────────────────────────────────────────────
create or replace function public.hc_list_words(
  p_filter text default 'recent',
  p_limit  integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
set timezone = 'Asia/Shanghai'
as $$
declare
  v_uid   uuid := auth.uid();
  v_limit integer := least(greatest(1, coalesce(p_limit, 50)), 200);
  v_off   integer := greatest(0, coalesce(p_offset, 0));
  v_rows  jsonb;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_filter not in ('recent', 'due', 'activated') then
    raise exception '未知的筛选 %，只有 recent / due / activated', p_filter;
  end if;

  with picked as (
    select w.*, s.activated_at,
      case p_filter
        when 'due'       then extract(epoch from w.due_at)
        when 'activated' then -extract(epoch from s.activated_at)
        else                  -extract(epoch from w.created_at)
      end as ord
    from public.words w
    left join public.hc_word_status s
      on s.user_id = w.user_id and s.word_id = w.id
    where w.user_id = v_uid
      and w.status <> 'ignored'
      and (
        p_filter <> 'due'
        or (w.status <> 'new' and w.due_at <= now())
      )
      and (p_filter <> 'activated' or s.activated_at is not null)
    order by ord
    limit v_limit offset v_off
  )
  select coalesce(
    jsonb_agg(
      to_jsonb(p) - 'ord' || jsonb_build_object(
        -- 与 hc_get_study_queue 返回同一个形状，客户端的 toCard() 才能直接复用
        'is_capture', (p.first_context is not null or p.first_source_url is not null)
      )
      order by p.ord
    ),
    '[]'::jsonb
  ) into v_rows
  from picked p;

  return v_rows;
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- S8「设置」写 hc_profiles。又一次：**不是自律，是物理限制** ——
-- `wx.request` 没有 PATCH，PostgREST 的更新只走 PATCH（`design.md` §11 ③）。
--
-- 只开放 daily_goal 一个字段。level_line 是首启测出来的，不给手改；
-- active_pack_ids 在 P2 恒为 {base}（§9.1），P4 有词包了再说。
-- ─────────────────────────────────────────────────────────────
create or replace function public.hc_update_profile(p_daily_goal integer)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.hc_profiles;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
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

revoke execute on function public.hc_list_words(text, integer, integer) from public, anon;
revoke execute on function public.hc_update_profile(integer) from public, anon;

grant execute on function public.hc_list_words(text, integer, integer) to authenticated;
grant execute on function public.hc_update_profile(integer) to authenticated;
