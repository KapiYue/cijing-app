-- 修复已部署 0008/0009 的账号写锁：RLS 谓词不能直读已撤权的内部锁表。
-- 同时解除 batch_id 的错误唯一约束；一次关联必须为两个账号写入同一个 batch。

alter table public.hc_account_data_locks
  drop constraint if exists hc_account_data_locks_batch_id_key;
create index if not exists hc_account_data_locks_batch_idx
  on public.hc_account_data_locks(batch_id);

create or replace function public.hc_account_data_write_unlocked(p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, pg_temp
set row_security = off
as $$
  select not exists (
    select 1 from public.hc_account_data_locks
    where user_id = p_user_id and expires_at > now()
  );
$$;
revoke all on function public.hc_account_data_write_unlocked(uuid) from public, anon;
grant execute on function public.hc_account_data_write_unlocked(uuid) to authenticated, service_role;

drop policy if exists "profiles_owner_all" on public.profiles;
create policy "profiles_owner_all" on public.profiles for all
using (auth.uid() = id and public.hc_account_data_write_unlocked(auth.uid()))
with check (auth.uid() = id and public.hc_account_data_write_unlocked(auth.uid()));

drop policy if exists "words_owner_all" on public.words;
create policy "words_owner_all" on public.words for all
using (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()))
with check (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()));
drop policy if exists "contexts_owner_all" on public.word_contexts;
create policy "contexts_owner_all" on public.word_contexts for all
using (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()))
with check (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()));
drop policy if exists "reviews_owner_all" on public.review_events;
create policy "reviews_owner_all" on public.review_events for all
using (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()))
with check (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()));
drop policy if exists "readings_owner_all" on public.reading_sessions;
create policy "readings_owner_all" on public.reading_sessions for all
using (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()))
with check (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()));
drop policy if exists "attempts_owner_all" on public.practice_attempts;
create policy "attempts_owner_all" on public.practice_attempts for all
using (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()))
with check (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()));
drop policy if exists "voice_owner_all" on public.voice_attempts;
create policy "voice_owner_all" on public.voice_attempts for all
using (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()))
with check (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()));
drop policy if exists "activity_owner_all" on public.daily_activity;
create policy "activity_owner_all" on public.daily_activity for all
using (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()))
with check (auth.uid() = user_id and public.hc_account_data_write_unlocked(auth.uid()));
