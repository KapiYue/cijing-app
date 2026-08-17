-- 补齐表级权限，让整套迁移能重建出一个能用的数据库（2026-08-17）
--
-- 202607200001_initial_schema.sql 建了九张表，一条表级 grant 都没写；整套迁移
-- 里唯一的表 grant 在 202607220001 第 45 行，只覆盖 reading_sessions——这正是
-- 它成为唯一可用表的原因。较新版本的 Supabase CLI 不再默认给 anon /
-- authenticated 发 public 表权限，要求显式 grant。
--
-- 生产之所以一直没事：托管项目建表时拿到了当时的默认权限，从未依赖迁移里的
-- grant。但 `supabase db reset` 出来的库里 authenticated 只有
-- TRIGGER/TRUNCATE/REFERENCES，连 get_daily_plan 都会 403：
--   permission denied for table profiles
-- 于是本机 E2E 跑不起来，更要紧的是生产若需从迁移重建（迁项目、恢复演练、开
-- 预发环境）会得到一个不可用的库，而且 db reset 全绿，报错要到运行时才出现。
--
-- **不放宽任何安全边界**：这九张表全部启用了 RLS 且带 owner 策略，grant 只是把
-- 门开到 RLS 面前，行级可见性仍由策略决定。reading_sessions 早就是这个状态，
-- 本迁移只是把其余八张拉齐。anon 不授予任何权限。
--
-- 幂等，可重复执行；应用到生产应为空操作（那边已有等效权限）。

grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.words to authenticated;
grant select, insert, update, delete on public.word_contexts to authenticated;
grant select, insert, update, delete on public.review_events to authenticated;
grant select, insert, update, delete on public.reading_sessions to authenticated;
grant select, insert, update, delete on public.practice_attempts to authenticated;
grant select, insert, update, delete on public.voice_attempts to authenticated;
grant select, insert, update, delete on public.daily_activity to authenticated;
grant select, insert, update, delete on public.lexicon_cache to authenticated;
