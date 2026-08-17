-- Supabase 保活探针（2026-08-17）
--
-- Supabase 免费版项目 7 天没有活动就会被暂停，暂停后整个后端下线：App 打不开、
-- 扩展查不了词。定时任务（.github/workflows/keepalive.yml）每两天调一次本函数，
-- 用最轻的方式产生一次真实的数据库查询。
--
-- 为什么要专门建个函数，而不是随便查张表：保活走的是 publishable key（anon 角色），
-- 而本项目九张业务表都没有给 anon 任何权限（见 202608170002），任意表查询都会返回
-- 403。403 也确实碰到了数据库，但它证明不了「数据库在正常应答」，而且把探针的成功
-- 判据建立在一个错误码上，日后一旦权限有变就会误报。
--
-- 安全性：不读任何表、不接参数、只返回当前时间。anon 能调它也拿不到任何业务数据。

create or replace function public.keepalive()
returns timestamptz
language sql
stable
as $$ select now() $$;

-- 函数默认对 PUBLIC 开放 execute，先收回再按需授予，避免隐式扩权。
revoke all on function public.keepalive() from public;
grant execute on function public.keepalive() to anon, authenticated;
