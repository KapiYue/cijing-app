-- 活词私有表。《执行方案》§4.1 / §4.1b / §4.1c / §4.5。
--
-- 落点规则（§14.1 T7）：共享 schema 只放「事实」，不放「解释」。
-- 本文件里的每一张表都是「解释」——词鲸不读，也不受影响。
--
-- RLS 一律 owner-only，用同一套 auth.uid()。

-- ─────────────────────────────────────────────────────────────
-- §4.1  hc_profiles：首启测试的产出物
-- ─────────────────────────────────────────────────────────────
create table if not exists public.hc_profiles (
  user_id            uuid primary key references auth.users(id) on delete cascade,
  -- 首启 30 词勾选测出的水平线，1–6 频段序号。NULL = 还没测
  level_line         smallint check (level_line between 1 and 6),
  daily_goal         integer not null default 20 check (daily_goal between 1 and 100),
  -- P2 恒为 {base}，P4 起用户可选
  active_pack_ids    text[] not null default array['base'],
  -- NULL = 没做完首启，进任何 tab 强制回到首启（§6.0 结尾）
  onboarding_done_at timestamptz,
  -- 首启第 1 屏勾的场景。**仅埋点用，P2 不影响算法**（§6.0 诚实标注）
  scenes             text[] not null default '{}',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

alter table public.hc_profiles enable row level security;

drop policy if exists hc_profiles_owner on public.hc_profiles;
create policy hc_profiles_owner on public.hc_profiles
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────
-- §4.1b  hc_word_status：§3.3 的落点
--
-- activated_at 一次写入、此后**永不改写**。
-- 理由：SM-2 的 interval 在 lapse 时被打回 1，若每次实时用 interval >= 21 判断，
-- 用户遗忘一次就会看到「已激活 83 个」变成 82 —— 这正是 §3.2 禁止的回退。
-- 它同时是北极星 Weekly Activated Words 的唯一数据源，**不是可选优化，是指标的前置条件**。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.hc_word_status (
  user_id      uuid not null references auth.users(id) on delete cascade,
  word_id      uuid not null references public.words(id) on delete cascade,
  activated_at timestamptz not null default now(),
  primary key (user_id, word_id)
);

create index if not exists hc_word_status_user_time_idx
  on public.hc_word_status (user_id, activated_at desc);

alter table public.hc_word_status enable row level security;

drop policy if exists hc_word_status_owner on public.hc_word_status;
create policy hc_word_status_owner on public.hc_word_status
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 「永不改写」的机器化版本：UPDATE 直接拒绝。
-- 靠代码自律守不住一个跨三端的不变量。
create or replace function public.hc_word_status_no_update()
returns trigger language plpgsql as $$
begin
  raise exception 'hc_word_status.activated_at 一次写入永不改写（《执行方案》§3.3）';
end;
$$;

drop trigger if exists hc_word_status_immutable on public.hc_word_status;
create trigger hc_word_status_immutable
  before update on public.hc_word_status
  for each row execute function public.hc_word_status_no_update();

-- ─────────────────────────────────────────────────────────────
-- §4.1c  hc_wechat_identities：微信身份映射
--
-- Supabase Auth 没有微信 provider，auth.identities 写不进去也不该直接写。
-- user_id 上的 UNIQUE = 一个账号只能绑一个微信。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.hc_wechat_identities (
  openid         text primary key,
  unionid        text,
  user_id        uuid not null unique references auth.users(id) on delete cascade,
  -- 派生密码的轮转版本（T3 未决项①：靠 secret_version 惰性重派生）
  secret_version integer not null default 1,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.hc_wechat_identities enable row level security;

-- 只有网关的 service_role 读写。客户端**一行都不该看到**——openid 是身份凭据。
drop policy if exists hc_wechat_identities_self_read on public.hc_wechat_identities;
create policy hc_wechat_identities_self_read on public.hc_wechat_identities
  for select using (false);

-- ─────────────────────────────────────────────────────────────
-- §4.5  hc_events：埋点。词鲸完全没有埋点，这张表是净新增。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.hc_events (
  id         bigserial primary key,
  user_id    uuid references auth.users(id) on delete set null,
  platform   text not null default 'mp' check (platform in ('mp', 'ext', 'ios', 'android')),
  name       text not null,
  props      jsonb not null default '{}'::jsonb,
  client_ts  timestamptz,
  server_ts  timestamptz not null default now(),
  session_id text
);
-- ⚠️ 不加 device 维度（§14.4 第 3 条：词鲸 schema 里没有，保持全局）

create index if not exists hc_events_name_time_idx on public.hc_events (name, server_ts);
create index if not exists hc_events_user_time_idx on public.hc_events (user_id, server_ts);

alter table public.hc_events enable row level security;

-- 只能写自己的，谁也读不了（分析走 service_role）
drop policy if exists hc_events_insert_self on public.hc_events;
create policy hc_events_insert_self on public.hc_events
  for insert with check (user_id = auth.uid());

drop policy if exists hc_events_no_read on public.hc_events;
create policy hc_events_no_read on public.hc_events
  for select using (false);

grant select, insert, update on public.hc_profiles to authenticated;
grant select, insert on public.hc_word_status to authenticated;
grant insert on public.hc_events to authenticated;
grant usage, select on sequence public.hc_events_id_seq to authenticated;

-- service_role 也必须显式 grant，理由同 202608170002：托管项目建表时拿到过历史
-- 默认权限，所以生产「碰巧能用」；但 `supabase db reset` 重建出来的库里
-- service_role 只有 REFERENCES/TRIGGER/TRUNCATE，上面两条注释所依赖的前提
-- （「只有网关的 service_role 读写」「分析走 service_role」）当场不成立。
-- 不补的后果是 db reset 全绿、网关和分析在运行时 403。
-- service_role 本来就绕过 RLS，这里只是把门开到 RLS 面前，不放宽任何边界。
grant select, insert, update on public.hc_wechat_identities to service_role;
grant select on public.hc_events to service_role;
