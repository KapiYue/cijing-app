-- Persist every generated reading per authenticated user. This migration is
-- deliberately idempotent so environments created before reading history was
-- introduced can be upgraded safely.
create table if not exists public.reading_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  subtitle text,
  theme text not null,
  style text not null,
  difficulty text not null,
  target_word_ids uuid[] not null default '{}',
  target_terms text[] not null default '{}',
  paragraphs jsonb not null default '[]'::jsonb,
  estimated_minutes integer not null default 5,
  cache_key text,
  is_cached boolean not null default false,
  translations_visible boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists reading_sessions_user_created_idx
  on public.reading_sessions(user_id, created_at desc);
create index if not exists reading_sessions_cache_idx
  on public.reading_sessions(user_id, cache_key, created_at desc);

alter table public.reading_sessions enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'reading_sessions'
      and policyname = 'readings_owner_all'
  ) then
    create policy "readings_owner_all" on public.reading_sessions for all
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end
$$;

grant select, insert, update, delete on public.reading_sessions to authenticated;

comment on table public.reading_sessions is
  'User-scoped history for generated readings; retained across app launches and sessions.';
