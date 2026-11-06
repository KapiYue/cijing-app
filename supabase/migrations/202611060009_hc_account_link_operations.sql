-- 账号关联的唯一写入口。仅网关持有的 service_role 可调用；客户端不能指定账号、
-- 不能直接写关系表，也不能在本地搬运学习数据。
--
-- 这份迁移只依赖词鲸当前已落地的 202607200001—202609010002 表结构。

-- 写锁由 RLS 强制执行，不依赖客户端是否记得检查。security definer 的迁移函数绕过
-- 这些策略，因此可在同一个事务内完成搬运；锁只在操作的短事务期间存在。
drop policy if exists "profiles_owner_all" on public.profiles;
create policy "profiles_owner_all" on public.profiles for all
using (auth.uid() = id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()))
with check (auth.uid() = id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()));
drop policy if exists "words_owner_all" on public.words;
create policy "words_owner_all" on public.words for all
using (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()))
with check (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()));
drop policy if exists "contexts_owner_all" on public.word_contexts;
create policy "contexts_owner_all" on public.word_contexts for all
using (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()))
with check (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()));
drop policy if exists "reviews_owner_all" on public.review_events;
create policy "reviews_owner_all" on public.review_events for all
using (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()))
with check (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()));
drop policy if exists "readings_owner_all" on public.reading_sessions;
create policy "readings_owner_all" on public.reading_sessions for all
using (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()))
with check (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()));
drop policy if exists "attempts_owner_all" on public.practice_attempts;
create policy "attempts_owner_all" on public.practice_attempts for all
using (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()))
with check (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()));
drop policy if exists "voice_owner_all" on public.voice_attempts;
create policy "voice_owner_all" on public.voice_attempts for all
using (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()))
with check (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()));
drop policy if exists "activity_owner_all" on public.daily_activity;
create policy "activity_owner_all" on public.daily_activity for all
using (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()))
with check (auth.uid() = user_id and not exists (select 1 from public.hc_account_data_locks l where l.user_id = auth.uid() and l.expires_at > now()));

create or replace function public.hc_execute_account_link(
  p_operation text,
  p_wechat_user_id uuid,
  p_cijing_user_id uuid,
  p_requested_by uuid,
  p_confirmation_version text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_batch uuid := gen_random_uuid();
  v_source uuid;
  v_target uuid;
  v_table text;
  v_source_count bigint;
  v_target_count bigint;
  v_session record;
  v_new_session_id uuid;
begin
  if current_user <> 'service_role' and auth.role() <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_operation not in ('link', 'unlink') or p_wechat_user_id is null
     or p_cijing_user_id is null or p_wechat_user_id = p_cijing_user_id then
    raise exception 'invalid account-link request' using errcode = '22023';
  end if;
  if nullif(btrim(p_confirmation_version), '') is null then
    raise exception 'missing confirmation version' using errcode = '22023';
  end if;

  -- 以稳定顺序锁两行 auth 用户，避免两条交叉关联请求彼此死锁。
  perform 1 from auth.users where id in (p_wechat_user_id, p_cijing_user_id) order by id for update;
  if (select count(*) from auth.users where id in (p_wechat_user_id, p_cijing_user_id)) <> 2 then
    raise exception 'account not found' using errcode = '22023';
  end if;

  insert into public.hc_account_link_batches (
    id, operation, wechat_user_id, cijing_user_id, requested_by, state, confirmation_version, started_at
  ) values (
    v_batch, p_operation, p_wechat_user_id, p_cijing_user_id, p_requested_by,
    'preparing', p_confirmation_version, now()
  );
  insert into public.hc_account_data_locks (user_id, batch_id, expires_at)
  values
    (p_wechat_user_id, v_batch, now() + interval '5 minutes'),
    (p_cijing_user_id, v_batch, now() + interval '5 minutes');
  insert into public.hc_account_link_audit (batch_id, actor_user_id, event, details)
  values (v_batch, p_requested_by, p_operation || '_started', jsonb_build_object('confirmation_version', p_confirmation_version));

  if p_operation = 'link' then
    if exists (select 1 from public.hc_account_links where wechat_user_id = p_wechat_user_id)
       or exists (select 1 from public.hc_account_links where cijing_user_id = p_cijing_user_id) then
      raise exception 'one of these accounts is already linked' using errcode = '23505';
    end if;
    v_source := p_wechat_user_id;
    v_target := p_cijing_user_id;
  else
    if not exists (
      select 1 from public.hc_account_links
      where wechat_user_id = p_wechat_user_id and cijing_user_id = p_cijing_user_id
    ) then
      raise exception 'account link not found' using errcode = '22023';
    end if;
    v_source := p_cijing_user_id;
    v_target := p_wechat_user_id;
  end if;

  -- Manifest 记录的是迁移前后的数量与确定性摘要，不含词文、身份凭据或认证证明。
  foreach v_table in array array['words', 'word_contexts', 'review_events', 'daily_activity',
                                  'reading_sessions', 'practice_attempts', 'voice_attempts',
                                  'hc_profiles', 'hc_word_status']
  loop
    execute format('select count(*) from public.%I where %I = $1', v_table,
      case when v_table = 'hc_profiles' then 'user_id' else 'user_id' end)
      into v_source_count using v_source;
    execute format('select count(*) from public.%I where %I = $1', v_table,
      case when v_table = 'hc_profiles' then 'user_id' else 'user_id' end)
      into v_target_count using v_target;
    insert into public.hc_account_link_manifest (batch_id, phase, table_name, source_count, target_count, checksum)
    values (v_batch, case when p_operation = 'link' then 'before_link' else 'before_unlink' end,
            v_table, v_source_count, v_target_count,
            md5(v_table || ':' || v_source_count::text || ':' || v_target_count::text));
  end loop;

  if p_operation = 'link' then
    -- 不冲突的词保留原 id（所有外键历史随之保留）并移到规范账号。
    update public.words s set user_id = v_target
    where s.user_id = v_source and not exists (
      select 1 from public.words t where t.user_id = v_target and t.normalized_term = s.normalized_term
    );

    -- 同词绝不删除。按最近学习状态更新规范词；历史记录、语境和练习改挂到该词。
    update public.words t set
      status = s.status, strength = s.strength, ease_factor = s.ease_factor, interval_days = s.interval_days,
      repetitions = s.repetitions, lapses = s.lapses, lookup_count = greatest(t.lookup_count, s.lookup_count),
      error_count = s.error_count, due_at = s.due_at, last_reviewed_at = s.last_reviewed_at,
      mastered_at = coalesce(s.mastered_at, t.mastered_at), updated_at = now()
    from public.words s
    where s.user_id = v_source and t.user_id = v_target and t.normalized_term = s.normalized_term
      and coalesce(s.last_reviewed_at, s.updated_at) > coalesce(t.last_reviewed_at, t.updated_at);
    update public.word_contexts c set user_id = v_target, word_id = t.id
    from public.words s join public.words t on t.user_id = v_target and t.normalized_term = s.normalized_term
    where c.user_id = v_source and c.word_id = s.id;
    update public.review_events e set user_id = v_target, word_id = t.id
    from public.words s join public.words t on t.user_id = v_target and t.normalized_term = s.normalized_term
    where e.user_id = v_source and e.word_id = s.id;
    update public.practice_attempts a set user_id = v_target, word_id = t.id
    from public.words s join public.words t on t.user_id = v_target and t.normalized_term = s.normalized_term
    where a.user_id = v_source and a.word_id = s.id;
    insert into public.hc_word_status (user_id, word_id, activated_at)
    select v_target, t.id, s.activated_at
    from public.hc_word_status s
    join public.words sw on sw.id = s.word_id and sw.user_id = v_source
    join public.words t on t.user_id = v_target and t.normalized_term = sw.normalized_term
    on conflict (user_id, word_id) do update set activated_at = least(hc_word_status.activated_at, excluded.activated_at);
    insert into public.daily_activity (
      user_id, activity_date, learned_count, reviewed_count, reading_count, practice_count, minutes, completed, updated_at
    )
    select v_target, activity_date, learned_count, reviewed_count, reading_count, practice_count, minutes, completed, now()
    from public.daily_activity where user_id = v_source
    on conflict (user_id, activity_date) do update set
      learned_count = daily_activity.learned_count + excluded.learned_count,
      reviewed_count = daily_activity.reviewed_count + excluded.reviewed_count,
      reading_count = daily_activity.reading_count + excluded.reading_count,
      practice_count = daily_activity.practice_count + excluded.practice_count,
      minutes = daily_activity.minutes + excluded.minutes,
      completed = daily_activity.completed or excluded.completed,
      updated_at = now();
    delete from public.daily_activity where user_id = v_source;
    update public.reading_sessions set user_id = v_target where user_id = v_source;
    update public.voice_attempts set user_id = v_target where user_id = v_source;
    update public.hc_profiles set user_id = v_target where user_id = v_source
      and not exists (select 1 from public.hc_profiles where user_id = v_target);
    update public.hc_word_status set user_id = v_target where user_id = v_source
      and not exists (select 1 from public.hc_word_status t where t.user_id = v_target and t.word_id = hc_word_status.word_id);
    insert into public.hc_account_links (wechat_user_id, cijing_user_id)
    values (p_wechat_user_id, p_cijing_user_id);
  else
    -- 解绑复制当前规范账号的词与私有状态。词使用新 id，避免破坏仍由规范账号持有的历史。
    insert into public.words (
      user_id, term, normalized_term, lemma, phonetic, audio_url, parts, primary_meaning, contextual_meaning,
      english_definition, example_en, example_zh, first_context, first_source_url, first_source_title, notes,
      custom_meaning, status, strength, ease_factor, interval_days, repetitions, lapses, lookup_count,
      error_count, due_at, last_reviewed_at, mastered_at, created_at, updated_at
    )
    select v_target, term, normalized_term, lemma, phonetic, audio_url, parts, primary_meaning, contextual_meaning,
      english_definition, example_en, example_zh, first_context, first_source_url, first_source_title, notes,
      custom_meaning, status, strength, ease_factor, interval_days, repetitions, lapses, lookup_count,
      error_count, due_at, last_reviewed_at, mastered_at, created_at, now()
    from public.words where user_id = v_source
    on conflict (user_id, normalized_term) do update set
      status = excluded.status, strength = excluded.strength, ease_factor = excluded.ease_factor,
      interval_days = excluded.interval_days, repetitions = excluded.repetitions, lapses = excluded.lapses,
      lookup_count = greatest(words.lookup_count, excluded.lookup_count), error_count = excluded.error_count,
      due_at = excluded.due_at, last_reviewed_at = excluded.last_reviewed_at,
      mastered_at = coalesce(excluded.mastered_at, words.mastered_at), updated_at = now();
    insert into public.word_contexts (user_id, word_id, context_text, contextual_meaning, sentence, source_url, source_title, created_at)
    select v_target, tw.id, c.context_text, c.contextual_meaning, c.sentence, c.source_url, c.source_title, c.created_at
    from public.word_contexts c
    join public.words sw on sw.id = c.word_id and sw.user_id = v_source
    join public.words tw on tw.user_id = v_target and tw.normalized_term = sw.normalized_term
    where c.user_id = v_source;
    insert into public.review_events (
      user_id, word_id, quality, exercise_type, response_time_ms, answer, expected_answer, client_event_id, created_at
    )
    select v_target, tw.id, e.quality, e.exercise_type, e.response_time_ms, e.answer, e.expected_answer, e.client_event_id, e.created_at
    from public.review_events e
    join public.words sw on sw.id = e.word_id and sw.user_id = v_source
    join public.words tw on tw.user_id = v_target and tw.normalized_term = sw.normalized_term
    where e.user_id = v_source
    on conflict do nothing;
    insert into public.daily_activity (
      user_id, activity_date, learned_count, reviewed_count, reading_count, practice_count, minutes, completed, updated_at
    )
    select v_target, activity_date, learned_count, reviewed_count, reading_count, practice_count, minutes, completed, now()
    from public.daily_activity where user_id = v_source
    on conflict (user_id, activity_date) do update set
      learned_count = daily_activity.learned_count + excluded.learned_count,
      reviewed_count = daily_activity.reviewed_count + excluded.reviewed_count,
      reading_count = daily_activity.reading_count + excluded.reading_count,
      practice_count = daily_activity.practice_count + excluded.practice_count,
      minutes = daily_activity.minutes + excluded.minutes,
      completed = daily_activity.completed or excluded.completed,
      updated_at = now();
    -- 新会话使用新 id；临时映射让语音历史保留对应的新会话关系，不把规范账号的 id 泄到微信副本。
    create temporary table _hc_unlink_session_map (source_id uuid primary key, target_id uuid not null) on commit drop;
    for v_session in select * from public.reading_sessions where user_id = v_source loop
      insert into public.reading_sessions (
        user_id, title, subtitle, theme, style, difficulty, target_word_ids, target_terms,
        paragraphs, estimated_minutes, cache_key, is_cached, translations_visible, completed_at, created_at
      ) values (
        v_target, v_session.title, v_session.subtitle, v_session.theme, v_session.style, v_session.difficulty,
        coalesce((
          select array_agg(tw.id order by u.ord)
          from unnest(v_session.target_word_ids) with ordinality as u(source_word_id, ord)
          join public.words sw on sw.id = u.source_word_id and sw.user_id = v_source
          join public.words tw on tw.user_id = v_target and tw.normalized_term = sw.normalized_term
        ), '{}'::uuid[]),
        v_session.target_terms, v_session.paragraphs, v_session.estimated_minutes, v_session.cache_key,
        v_session.is_cached, v_session.translations_visible, v_session.completed_at, v_session.created_at
      ) returning id into v_new_session_id;
      insert into _hc_unlink_session_map (source_id, target_id) values (v_session.id, v_new_session_id);
    end loop;
    insert into public.voice_attempts (
      user_id, reading_session_id, paragraph_index, expected_text, recognized_text, accuracy, created_at
    )
    select v_target, m.target_id, a.paragraph_index, a.expected_text, a.recognized_text, a.accuracy, a.created_at
    from public.voice_attempts a
    join _hc_unlink_session_map m on m.source_id = a.reading_session_id
    where a.user_id = v_source;
    insert into public.practice_attempts (
      user_id, reading_session_id, word_id, exercise_type, prompt, answer, expected_answer, is_correct, quality, response_time_ms, created_at
    )
    select v_target, m.target_id, tw.id, a.exercise_type, a.prompt, a.answer, a.expected_answer,
      a.is_correct, a.quality, a.response_time_ms, a.created_at
    from public.practice_attempts a
    join public.words sw on sw.id = a.word_id and sw.user_id = v_source
    join public.words tw on tw.user_id = v_target and tw.normalized_term = sw.normalized_term
    left join _hc_unlink_session_map m on m.source_id = a.reading_session_id
    where a.user_id = v_source;
    insert into public.hc_profiles (user_id, level_line, daily_goal, active_pack_ids, onboarding_done_at, scenes, created_at, updated_at)
    select v_target, level_line, daily_goal, active_pack_ids, onboarding_done_at, scenes, now(), now()
    from public.hc_profiles where user_id = v_source
    on conflict (user_id) do update set daily_goal = excluded.daily_goal, updated_at = now();
    insert into public.hc_word_status (user_id, word_id, activated_at)
    select v_target, tw.id, s.activated_at
    from public.hc_word_status s
    join public.words sw on sw.id = s.word_id and sw.user_id = v_source
    join public.words tw on tw.user_id = v_target and tw.normalized_term = sw.normalized_term
    where s.user_id = v_source
    on conflict (user_id, word_id) do update set activated_at = least(hc_word_status.activated_at, excluded.activated_at);
    delete from public.hc_account_links where wechat_user_id = p_wechat_user_id;
  end if;

  foreach v_table in array array['words', 'word_contexts', 'review_events', 'daily_activity',
                                  'reading_sessions', 'practice_attempts', 'voice_attempts',
                                  'hc_profiles', 'hc_word_status']
  loop
    execute format('select count(*) from public.%I where user_id = $1', v_table) into v_source_count using v_source;
    execute format('select count(*) from public.%I where user_id = $1', v_table) into v_target_count using v_target;
    insert into public.hc_account_link_manifest (batch_id, phase, table_name, source_count, target_count, checksum)
    values (v_batch, case when p_operation = 'link' then 'after_link' else 'after_unlink' end,
            v_table, v_source_count, v_target_count,
            md5(v_table || ':' || v_source_count::text || ':' || v_target_count::text));
  end loop;
  update public.hc_account_link_batches set state = 'committed', finished_at = now() where id = v_batch;
  insert into public.hc_account_link_audit (batch_id, actor_user_id, event, details)
  values (v_batch, p_requested_by, p_operation || '_committed', '{}'::jsonb);
  delete from public.hc_account_data_locks where batch_id = v_batch;
  return jsonb_build_object('batch_id', v_batch, 'operation', p_operation, 'state', 'committed');
exception when others then
  -- 整个函数处于同一事务：数据/关系/锁不会半提交；错误文本不写审计，避免落入上游凭据。
  raise;
end;
$$;

revoke execute on function public.hc_execute_account_link(text, uuid, uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.hc_execute_account_link(text, uuid, uuid, uuid, text) to service_role;
