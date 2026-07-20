create extension if not exists pgcrypto;

create type public.word_learning_status as enum (
  'new', 'learning', 'review', 'weak', 'mastered', 'ignored'
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  daily_new_goal integer not null default 8 check (daily_new_goal between 1 and 50),
  daily_review_goal integer not null default 20 check (daily_review_goal between 1 and 100),
  preferred_difficulty text not null default 'intermediate',
  preferred_theme text not null default 'daily_life',
  preferred_style text not null default 'story',
  timezone text not null default 'Asia/Shanghai',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.words (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  term text not null,
  normalized_term text not null,
  lemma text not null,
  phonetic text,
  audio_url text,
  parts jsonb not null default '[]'::jsonb,
  primary_meaning text not null,
  contextual_meaning text,
  english_definition text,
  example_en text,
  example_zh text,
  first_context text,
  first_source_url text,
  first_source_title text,
  notes text not null default '',
  custom_meaning text,
  status public.word_learning_status not null default 'new',
  strength real not null default 0 check (strength between 0 and 1),
  ease_factor real not null default 2.5 check (ease_factor between 1.3 and 3.5),
  interval_days integer not null default 0 check (interval_days >= 0),
  repetitions integer not null default 0 check (repetitions >= 0),
  lapses integer not null default 0 check (lapses >= 0),
  lookup_count integer not null default 1 check (lookup_count >= 1),
  error_count integer not null default 0 check (error_count >= 0),
  due_at timestamptz not null default now(),
  last_reviewed_at timestamptz,
  mastered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, normalized_term)
);

create index words_user_status_due_idx on public.words(user_id, status, due_at);
create index words_user_created_idx on public.words(user_id, created_at desc);
create index words_term_search_idx on public.words(user_id, normalized_term text_pattern_ops);

create table public.word_contexts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  word_id uuid not null references public.words(id) on delete cascade,
  context_text text not null,
  contextual_meaning text,
  sentence text,
  source_url text,
  source_title text,
  created_at timestamptz not null default now()
);

create index word_contexts_word_idx on public.word_contexts(word_id, created_at desc);

create table public.review_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  word_id uuid not null references public.words(id) on delete cascade,
  quality integer not null check (quality between 0 and 5),
  exercise_type text not null,
  response_time_ms integer,
  answer text,
  expected_answer text,
  created_at timestamptz not null default now()
);

create index review_events_user_created_idx on public.review_events(user_id, created_at desc);
create index review_events_word_created_idx on public.review_events(word_id, created_at desc);

create table public.reading_sessions (
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

create index reading_sessions_user_created_idx on public.reading_sessions(user_id, created_at desc);
create index reading_sessions_cache_idx on public.reading_sessions(user_id, cache_key, created_at desc);

create table public.practice_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reading_session_id uuid references public.reading_sessions(id) on delete set null,
  word_id uuid not null references public.words(id) on delete cascade,
  exercise_type text not null,
  prompt jsonb not null default '{}'::jsonb,
  answer text,
  expected_answer text,
  is_correct boolean not null,
  quality integer not null check (quality between 0 and 5),
  response_time_ms integer,
  created_at timestamptz not null default now()
);

create table public.voice_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reading_session_id uuid references public.reading_sessions(id) on delete cascade,
  paragraph_index integer not null,
  expected_text text not null,
  recognized_text text not null,
  accuracy real not null check (accuracy between 0 and 1),
  created_at timestamptz not null default now()
);

create table public.daily_activity (
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  learned_count integer not null default 0,
  reviewed_count integer not null default 0,
  reading_count integer not null default 0,
  practice_count integer not null default 0,
  minutes integer not null default 0,
  completed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, activity_date)
);

create table public.lexicon_cache (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  normalized_term text not null,
  context_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '90 days',
  unique (user_id, normalized_term, context_hash)
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger words_set_updated_at before update on public.words
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.words enable row level security;
alter table public.word_contexts enable row level security;
alter table public.review_events enable row level security;
alter table public.reading_sessions enable row level security;
alter table public.practice_attempts enable row level security;
alter table public.voice_attempts enable row level security;
alter table public.daily_activity enable row level security;
alter table public.lexicon_cache enable row level security;

create policy "profiles_owner_all" on public.profiles for all
using (auth.uid() = id) with check (auth.uid() = id);
create policy "words_owner_all" on public.words for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "contexts_owner_all" on public.word_contexts for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "reviews_owner_all" on public.review_events for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "readings_owner_all" on public.reading_sessions for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "attempts_owner_all" on public.practice_attempts for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "voice_owner_all" on public.voice_attempts for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "activity_owner_all" on public.daily_activity for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "cache_owner_all" on public.lexicon_cache for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);

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
    first_context, first_source_url, first_source_title
  ) values (
    v_user_id,
    p_payload ->> 'term', v_normalized, coalesce(nullif(p_payload ->> 'lemma', ''), p_payload ->> 'term'),
    p_payload ->> 'phonetic', p_payload ->> 'audio_url', coalesce(p_payload -> 'parts', '[]'::jsonb),
    coalesce(p_payload ->> 'primary_meaning', '待补充'), p_payload ->> 'contextual_meaning',
    p_payload ->> 'english_definition', p_payload ->> 'example_en', p_payload ->> 'example_zh',
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

create or replace function public.apply_review(
  p_word_id uuid,
  p_quality integer,
  p_exercise_type text default 'self_rating',
  p_response_time_ms integer default null,
  p_answer text default null,
  p_expected_answer text default null
)
returns public.words
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_word public.words;
  v_interval integer;
  v_ease real;
  v_repetitions integer;
  v_status public.word_learning_status;
  v_strength real;
begin
  if p_quality < 0 or p_quality > 5 then raise exception 'quality must be 0...5'; end if;
  select * into v_word from public.words
  where id = p_word_id and user_id = auth.uid() for update;
  if not found then raise exception 'Word not found'; end if;

  v_ease := greatest(1.3, least(3.5,
    v_word.ease_factor + (0.1 - (5 - p_quality) * (0.08 + (5 - p_quality) * 0.02))));

  if p_quality < 3 then
    v_repetitions := 0;
    v_interval := 1;
    v_status := 'weak';
    v_strength := greatest(0, v_word.strength - 0.18);
  else
    v_repetitions := v_word.repetitions + 1;
    v_interval := case
      when v_repetitions = 1 then 1
      when v_repetitions = 2 then 3
      else greatest(1, round(greatest(v_word.interval_days, 3) * v_ease *
        case when p_quality = 3 then 0.75 when p_quality = 5 then 1.2 else 1 end)::integer)
    end;
    v_strength := least(1, v_word.strength + (0.08 + p_quality * 0.025));
    v_status := case
      when v_strength >= 0.86 and v_interval >= 21 then 'mastered'
      when v_repetitions <= 1 then 'learning'
      else 'review'
    end;
  end if;

  update public.words set
    ease_factor = v_ease,
    interval_days = v_interval,
    repetitions = v_repetitions,
    lapses = lapses + case when p_quality < 3 then 1 else 0 end,
    error_count = error_count + case when p_quality < 3 then 1 else 0 end,
    strength = v_strength,
    status = v_status,
    due_at = now() + make_interval(days => v_interval),
    last_reviewed_at = now(),
    mastered_at = case when v_status = 'mastered' then coalesce(mastered_at, now()) else mastered_at end
  where id = p_word_id returning * into v_word;

  insert into public.review_events (
    user_id, word_id, quality, exercise_type, response_time_ms, answer, expected_answer
  ) values (
    auth.uid(), p_word_id, p_quality, p_exercise_type, p_response_time_ms, p_answer, p_expected_answer
  );

  insert into public.daily_activity (user_id, activity_date, reviewed_count, practice_count)
  values (auth.uid(), current_date, 1, case when p_exercise_type = 'self_rating' then 0 else 1 end)
  on conflict (user_id, activity_date) do update set
    reviewed_count = daily_activity.reviewed_count + 1,
    practice_count = daily_activity.practice_count + excluded.practice_count,
    completed = daily_activity.completed or (
      daily_activity.reading_count > 0 and daily_activity.practice_count + excluded.practice_count >= 5
    ),
    updated_at = now();

  return v_word;
end;
$$;

create or replace function public.get_daily_plan()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
with p as (
  select * from profiles where id = auth.uid()
), counts as (
  select
    count(*) filter (where status not in ('new', 'ignored') and due_at <= now()) as review_due,
    count(*) filter (where status = 'new') as new_available,
    count(*) filter (where status = 'weak') as weak_count,
    count(*) filter (where status <> 'ignored') as learned_count,
    count(*) filter (where status = 'mastered') as mastered_count
  from words where user_id = auth.uid()
), today as (
  select coalesce(reviewed_count, 0) as reviewed_count,
         coalesce(practice_count, 0) as practice_count,
         coalesce(reading_count, 0) as reading_count,
         coalesce(completed, false) as completed
  from daily_activity where user_id = auth.uid() and activity_date = current_date
), streak as (
  select count(*) as days from (
    select activity_date,
      activity_date - (row_number() over (order by activity_date))::integer as grp
    from daily_activity
    where user_id = auth.uid() and (reviewed_count > 0 or reading_count > 0)
  ) s
  where grp = (
    select max(activity_date - rn::integer) from (
      select activity_date, row_number() over (order by activity_date) rn
      from daily_activity
      where user_id = auth.uid() and (reviewed_count > 0 or reading_count > 0)
    ) z
  )
)
select jsonb_build_object(
  'review_due', least(c.review_due, p.daily_review_goal),
  'new_suggested', least(c.new_available, p.daily_new_goal),
  'weak_count', c.weak_count,
  'learned_count', c.learned_count,
  'mastered_count', c.mastered_count,
  'streak_days', coalesce(s.days, 0),
  'reviewed_today', coalesce(t.reviewed_count, 0),
  'practice_today', coalesce(t.practice_count, 0),
  'reading_today', coalesce(t.reading_count, 0),
  'completed_today', coalesce(t.completed, false),
  'daily_new_goal', p.daily_new_goal,
  'daily_review_goal', p.daily_review_goal
)
from p cross join counts c cross join streak s left join today t on true;
$$;

create or replace function public.get_learning_targets(p_limit integer default 10)
returns setof public.words
language sql
stable
security invoker
set search_path = public
as $$
  select * from public.words
  where user_id = auth.uid() and status <> 'ignored'
  order by
    case
      when status = 'weak' then 0
      when due_at <= now() and status <> 'new' then 1
      when status = 'new' then 2
      when status = 'learning' then 3
      else 4
    end,
    case when status = 'new' then created_at end asc,
    due_at asc,
    strength asc
  limit greatest(1, least(p_limit, 20));
$$;

create or replace function public.mark_reading_complete(p_reading_id uuid, p_minutes integer default 5)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_completed_at timestamptz;
begin
  select completed_at into v_completed_at from public.reading_sessions
  where id = p_reading_id and user_id = auth.uid() for update;
  if not found then raise exception 'Reading not found'; end if;

  if v_completed_at is not null then return; end if;
  update public.reading_sessions set completed_at = now() where id = p_reading_id;

  insert into public.daily_activity (user_id, activity_date, reading_count, minutes)
  values (auth.uid(), current_date, 1, greatest(1, p_minutes))
  on conflict (user_id, activity_date) do update set
    reading_count = daily_activity.reading_count + 1,
    minutes = daily_activity.minutes + excluded.minutes,
    completed = daily_activity.completed or daily_activity.practice_count >= 5,
    updated_at = now();
end;
$$;

revoke execute on function public.save_word(jsonb) from public, anon;
revoke execute on function public.apply_review(uuid, integer, text, integer, text, text) from public, anon;
revoke execute on function public.get_daily_plan() from public, anon;
revoke execute on function public.get_learning_targets(integer) from public, anon;
revoke execute on function public.mark_reading_complete(uuid, integer) from public, anon;

grant execute on function public.save_word(jsonb) to authenticated;
grant execute on function public.apply_review(uuid, integer, text, integer, text, text) to authenticated;
grant execute on function public.get_daily_plan() to authenticated;
grant execute on function public.get_learning_targets(integer) to authenticated;
grant execute on function public.mark_reading_complete(uuid, integer) to authenticated;
