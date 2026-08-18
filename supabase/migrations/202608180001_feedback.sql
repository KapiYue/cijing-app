-- 应用内意见反馈（2026-08-18）
--
-- 此前 App 里唯一的反馈通道是 `mailto:zdjoey@126.com`：用户要跳出 App、有配置好的
-- 邮件客户端、自己写清楚版本和机型，才能把一句话送到维护者手上。绝大多数人到第一步
-- 就放弃了，等于上架后基本收不到反馈。
--
-- 这张表把反馈收进库里：设置页直接提交，客户端顺带附上版本/机型/系统，用户也能回看
-- 自己提过什么、维护者回了什么。邮件通道保留，作为登录态失效时的兜底。

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category text not null default 'other'
    check (category in ('bug', 'suggestion', 'content', 'account', 'other')),
  -- 与客户端计数器同一个上限；btrim 后再算长度，挡住纯空白提交。
  content text not null check (char_length(btrim(content)) between 1 and 300),
  -- 可选回信方式。用户不填就按注册邮箱回，填了以这里为准。
  contact text check (char_length(contact) <= 120),
  app_version text check (char_length(app_version) <= 40),
  device text check (char_length(device) <= 80),
  os_version text check (char_length(os_version) <= 40),
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved')),
  reply text,
  replied_at timestamptz,
  created_at timestamptz not null default now()
);

-- 用户查自己的历史（倒序）；维护者在 Dashboard 里按状态捞待处理的。
create index if not exists feedback_user_created_idx on public.feedback (user_id, created_at desc);
create index if not exists feedback_status_created_idx on public.feedback (status, created_at desc);

alter table public.feedback enable row level security;

-- 只给 insert 和 select，都限本人：反馈一旦提交用户不能改也不能删，否则维护者手上的
-- 记录会在处理途中变样。status / reply 由维护者用 service role 在 Dashboard 里写，
-- 那条路径绕过 RLS，客户端拿不到 update/delete 权限。
drop policy if exists "feedback_insert_own" on public.feedback;
create policy "feedback_insert_own" on public.feedback for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "feedback_select_own" on public.feedback;
create policy "feedback_select_own" on public.feedback for select to authenticated
  using (auth.uid() = user_id);

grant select, insert on public.feedback to authenticated;

-- 刻意不做插入限流。项目还在拉新阶段，任何多余的门槛都是负收益；真出现灌库再补一条
-- 前向迁移加触发器，那时也能按真实数据定阈值，而不是现在拍一个。
