alter table public.words
  add column if not exists dictionary_attribution jsonb;

create or replace function public.save_word(p_payload jsonb)
returns public.words
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_word public.words;
  v_normalized text := lower(trim(p_payload ->> 'lemma'));
  v_context text := nullif(trim(p_payload ->> 'context'), '');
  v_is_new boolean;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;
  if v_normalized is null or v_normalized = '' then
    v_normalized := lower(trim(p_payload ->> 'term'));
  end if;
  v_is_new := not exists (
    select 1 from public.words where user_id = v_user_id and normalized_term = v_normalized
  );

  insert into public.words (
    user_id, term, normalized_term, lemma, phonetic, audio_url, parts,
    primary_meaning, contextual_meaning, english_definition, example_en, example_zh,
    dictionary_attribution, first_context, first_source_url, first_source_title
  ) values (
    v_user_id,
    p_payload ->> 'term', v_normalized, coalesce(nullif(p_payload ->> 'lemma', ''), p_payload ->> 'term'),
    p_payload ->> 'phonetic', p_payload ->> 'audio_url', coalesce(p_payload -> 'parts', '[]'::jsonb),
    coalesce(p_payload ->> 'primary_meaning', '待补充'), p_payload ->> 'contextual_meaning',
    p_payload ->> 'english_definition', p_payload ->> 'example_en', p_payload ->> 'example_zh',
    p_payload -> 'dictionary_attribution',
    v_context, p_payload ->> 'source_url', p_payload ->> 'source_title'
  )
  on conflict (user_id, normalized_term) do update set
    term = excluded.term,
    phonetic = coalesce(excluded.phonetic, words.phonetic),
    audio_url = coalesce(excluded.audio_url, words.audio_url),
    parts = case when excluded.parts = '[]'::jsonb then words.parts else excluded.parts end,
    primary_meaning = coalesce(nullif(excluded.primary_meaning, '待补充'), words.primary_meaning),
    contextual_meaning = coalesce(excluded.contextual_meaning, words.contextual_meaning),
    english_definition = coalesce(excluded.english_definition, words.english_definition),
    example_en = coalesce(excluded.example_en, words.example_en),
    example_zh = coalesce(excluded.example_zh, words.example_zh),
    dictionary_attribution = coalesce(excluded.dictionary_attribution, words.dictionary_attribution),
    lookup_count = words.lookup_count + 1,
    updated_at = now()
  returning * into v_word;

  if v_context is not null and not exists (
    select 1 from public.word_contexts
    where word_id = v_word.id and context_text = v_context
  ) then
    insert into public.word_contexts (
      user_id, word_id, context_text, contextual_meaning, sentence, source_url, source_title
    ) values (
      v_user_id, v_word.id, v_context, p_payload ->> 'contextual_meaning',
      p_payload ->> 'sentence', p_payload ->> 'source_url', p_payload ->> 'source_title'
    );
  end if;

  if v_is_new then
    insert into public.daily_activity (user_id, activity_date, learned_count)
    values (v_user_id, current_date, 1)
    on conflict (user_id, activity_date) do update set
      learned_count = daily_activity.learned_count + 1,
      updated_at = now();
  end if;

  return v_word;
end;
$$;
