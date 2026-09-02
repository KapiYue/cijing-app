-- 日界改为北京时间（2026-09-01）
--
-- 问题：所有写 / 读 daily_activity 的函数都用 current_date，它取数据库时区
-- （Supabase 默认 UTC）。于是北京时间 00:00–08:00 的学习被记进**前一天**：
--   · 早 7 点复习 → 写进昨天那一行，首页「今日已复习」显示 0；
--   · 昨天已 completed 的行被今早的复习继续累加，「连续 N 天」多算或断链；
--   · get_daily_plan 的 streak 判据 `activity_date >= current_date - 1`
--     在 UTC 08:00 前把「今天」当成昨天，连续段提前一天判死。
--
-- 改法：不改函数体，只给这些函数挂 `SET timezone`。函数级 GUC 在函数进入时
-- 生效、退出时还原，所以：
--   · 函数体内的 current_date 直接变成北京日期（这正是要的）；
--   · 函数返回值的 JSON 序列化发生在函数之外，仍按会话时区（UTC）渲染，
--     **已上线的 iOS 1.0 与 Chrome 扩展解析 timestamptz 的行为零变化**；
--   · 不需要把 5 个函数体抄一遍，也就不会与待做的 review_events.client_event_id
--     幂等改造（那份迁移要重写 apply_review 的函数体）打架。
--
-- 为什么写死 'Asia/Shanghai' 而不是 coalesce(profiles.timezone, ...)：
-- profiles.timezone 存在且 not null default 'Asia/Shanghai'，但**没有任何端
-- 提供修改入口**（iOS 只是把读到的值原样 PATCH 回去），实际取值恒为上海。
-- 等真出现跨时区用户，再把这些函数改成按 profiles.timezone 取日期；那时
-- 删掉本迁移的 ALTER 即可，是可逆的一步。
--
-- 不做回填。生产此刻有 8 个真实账号、26 行 daily_activity，维护者 2026-09-02 拍板
-- 不补历史归属；原因见文件末尾。
--
-- ⚠️ 生产的应用顺序与本文件的编号相反：202609010002 先被手工执行了，
--    apply_review 的 6 参数签名早已被它 drop 掉。所以**在生产按本文件原样重跑
--    会报 42883**，必须去掉下面那条 apply_review 的 ALTER（它的时区 GUC 由 0002
--    的函数体自带，已经在了）。全新库按编号顺序重放不受影响：那时 6 参数版还在。

alter function public.save_word(jsonb)
  set timezone = 'Asia/Shanghai';
alter function public.apply_review(uuid, integer, text, integer, text, text)
  set timezone = 'Asia/Shanghai';
alter function public.mark_reading_complete(uuid, integer)
  set timezone = 'Asia/Shanghai';
alter function public.complete_daily_session()
  set timezone = 'Asia/Shanghai';
alter function public.record_reading_generation()
  set timezone = 'Asia/Shanghai';
alter function public.get_daily_plan()
  set timezone = 'Asia/Shanghai';

-- 自检：任何提到 daily_activity 的函数都必须挂上时区，漏一个就让同一天分裂成两行。
-- 将来新增写 daily_activity 的函数而忘了挂，这个断言会在下一次全量重放迁移时炸出来。
do $$
declare
  v_missing text;
begin
  select string_agg(p.oid::regprocedure::text, ', ')
    into v_missing
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosrc like '%daily_activity%'
    and not exists (
      select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
      where lower(cfg) = lower('TimeZone=Asia/Shanghai')
    );
  if v_missing is not null then
    raise exception '这些函数读写 daily_activity 但没有设置时区: %', v_missing;
  end if;
end
$$;

-- 关于回填：没有通用的正确回填。daily_activity 只有日期没有时刻，UTC 那天的
-- 哪几次学习属于北京的第二天，行里已经看不出来了。真要精确重算，只能从
-- review_events（append-only，带 created_at）重放 —— 别猜。88 条事件重放是可行的，
-- 但维护者判断这批早期数据不值得补，明确放弃。
