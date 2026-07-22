alter table public.profiles
  add column if not exists preferred_voice_identifier text not null default '';

comment on column public.profiles.preferred_voice_identifier is
  'Apple AVSpeechSynthesisVoice identifier selected by the user and synced across signed-in devices.';
