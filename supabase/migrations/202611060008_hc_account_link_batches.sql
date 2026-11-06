-- 微信关联词鲸账号的服务端状态：认证映射保持不动，关联关系与数据迁移单独可审计。

create table public.hc_account_links (
  wechat_user_id uuid primary key references auth.users(id) on delete restrict,
  cijing_user_id uuid not null unique references auth.users(id) on delete restrict,
  linked_at timestamptz not null default now(),
  check (wechat_user_id <> cijing_user_id)
);

create table public.hc_account_link_batches (
  id uuid primary key default gen_random_uuid(),
  operation text not null check (operation in ('link', 'unlink')),
  wechat_user_id uuid not null references auth.users(id) on delete restrict,
  cijing_user_id uuid not null references auth.users(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  state text not null default 'pending_confirmation'
    check (state in ('pending_confirmation', 'preparing', 'committed', 'rolled_back', 'failed')),
  confirmation_version text not null,
  error_code text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  check (wechat_user_id <> cijing_user_id)
);
create unique index hc_account_link_batches_open_wechat_uidx
  on public.hc_account_link_batches (wechat_user_id)
  where state in ('pending_confirmation', 'preparing');
create unique index hc_account_link_batches_open_cijing_uidx
  on public.hc_account_link_batches (cijing_user_id)
  where state in ('pending_confirmation', 'preparing');

create table public.hc_account_link_audit (
  id bigserial primary key,
  batch_id uuid not null references public.hc_account_link_batches(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  event text not null,
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  check (not (details ?| array['password', 'token', 'openid', 'unionid', 'authorization']))
);
create index hc_account_link_audit_batch_time_idx on public.hc_account_link_audit(batch_id, occurred_at);

create table public.hc_account_data_locks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  batch_id uuid not null unique references public.hc_account_link_batches(id) on delete cascade,
  locked_at timestamptz not null default now(),
  expires_at timestamptz not null,
  check (expires_at > locked_at)
);

create table public.hc_account_link_manifest (
  batch_id uuid not null references public.hc_account_link_batches(id) on delete cascade,
  phase text not null check (phase in ('before_link', 'after_link', 'before_unlink', 'after_unlink')),
  table_name text not null,
  source_count bigint not null check (source_count >= 0),
  target_count bigint not null check (target_count >= 0),
  checksum text not null,
  primary key (batch_id, phase, table_name)
);

alter table public.hc_account_links enable row level security;
alter table public.hc_account_link_batches enable row level security;
alter table public.hc_account_link_audit enable row level security;
alter table public.hc_account_data_locks enable row level security;
alter table public.hc_account_link_manifest enable row level security;

revoke all on public.hc_account_links, public.hc_account_link_batches, public.hc_account_link_audit,
  public.hc_account_data_locks, public.hc_account_link_manifest from anon, authenticated;
grant select, insert, update, delete on public.hc_account_links, public.hc_account_link_batches,
  public.hc_account_link_audit, public.hc_account_data_locks, public.hc_account_link_manifest to service_role;
grant usage, select on sequence public.hc_account_link_audit_id_seq to service_role;
