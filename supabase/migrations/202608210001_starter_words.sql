-- 新用户注册即赠送一份新手词库（2026-08-21）
--
-- 现状：注册后词库是空的，而 generate-reading 在 index.ts:69 要求「至少 3 个
-- 单词」，否则返回 NOT_ENOUGH_WORDS。于是新账号进来看到的是——首页今日计划全
-- 是 0、生成短文报错、练习和跟读因为没有短文而全部不可用。整条主流程要用户先
-- 装好 Chrome 扩展、在网页上划词收藏够 3 个词才能跑通，等于把体验门槛前置到了
-- 产品之外。设置里那个「导入演示词库」是给审核演示账号用的，藏得太深，普通用
-- 户不会去点。
--
-- 做法：把词表落成一张**全局**表（不带 user_id），注册触发器从里面拷一份到用户
-- 自己的 words。落表而不是把 8 条 insert 硬写进触发器函数，是为了以后增删调整
-- 词表只需要一条普通 INSERT/UPDATE，不必再写迁移、也不必发版。

create table if not exists public.starter_words (
  id uuid primary key default gen_random_uuid(),
  term text not null unique,
  lemma text not null,
  phonetic text,
  parts jsonb not null default '[]'::jsonb,
  primary_meaning text not null,
  contextual_meaning text,
  example_en text,
  example_zh text,
  -- 排序决定拷进 words 时的 created_at 先后，进而决定词库列表的默认顺序。
  sort_order integer not null default 0,
  -- 下架一个词用 is_active = false，不要删行：删了会让「这个词曾经发过」的历史
  -- 无从查起，而留着行不影响已注册用户（他们的词是拷贝，早已独立）。
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.starter_words enable row level security;

-- 全局共享的只读词表：任何登录用户都能看（客户端若想做「新手词库预览」可以直接
-- 读），但谁都不能写——维护走后台 / SQL editor。anon 不授予任何权限。
drop policy if exists "starter_words_read" on public.starter_words;
create policy "starter_words_read" on public.starter_words for select
using (auth.role() = 'authenticated');

grant select on public.starter_words to authenticated;

-- 首批 8 个词，与客户端 AppStore.swift:513 的 DemoLexicon 保持一致，避免同一款
-- 产品出现两份说法不同的「起步词表」。8 个的量是按下游需求定的：generate-reading
-- 要 ≥3，练习题的干扰项从目标词的释义里取（PracticeSessionView.swift:475），
-- 少于 4 个词选项就凑不齐。
insert into public.starter_words
  (term, lemma, phonetic, parts, primary_meaning, contextual_meaning, example_en, example_zh, sort_order)
values
  ('resilient', 'resilient', 'rɪˈzɪliənt', '[{"partOfSpeech":"adj.","meaning":"有韧性的；能迅速恢复的"}]'::jsonb,
   '有韧性的；能迅速恢复的', '有韧性的；能迅速恢复的',
   'The resilient community rebuilt after the storm.', '暴风雨后，这个坚韧的社区完成了重建。', 1),
  ('subtle', 'subtle', 'ˈsʌtəl', '[{"partOfSpeech":"adj.","meaning":"微妙的；不易察觉的"}]'::jsonb,
   '微妙的；不易察觉的', '微妙的；不易察觉的',
   'A subtle change in tone altered the whole conversation.', '语气的微妙变化改变了整场对话。', 2),
  ('navigate', 'navigate', 'ˈnævəˌɡeɪt', '[{"partOfSpeech":"v.","meaning":"应对；导航"}]'::jsonb,
   '应对；导航', '应对；导航',
   'She learned to navigate a complex workplace.', '她学会了应对复杂的职场环境。', 3),
  ('sustain', 'sustain', 'səˈsteɪn', '[{"partOfSpeech":"v.","meaning":"维持；支撑"}]'::jsonb,
   '维持；支撑', '维持；支撑',
   'Curiosity can sustain a lifetime of learning.', '好奇心能支撑终身学习。', 4),
  ('inevitable', 'inevitable', 'ɪnˈevɪtəbəl', '[{"partOfSpeech":"adj.","meaning":"不可避免的"}]'::jsonb,
   '不可避免的', '不可避免的',
   'Some uncertainty is inevitable when plans change.', '计划改变时，一些不确定性不可避免。', 5),
  ('perspective', 'perspective', 'pərˈspɛktɪv', '[{"partOfSpeech":"n.","meaning":"视角；观点"}]'::jsonb,
   '视角；观点', '视角；观点',
   'Travel gave him a broader perspective.', '旅行给了他更广阔的视角。', 6),
  ('convey', 'convey', 'kənˈveɪ', '[{"partOfSpeech":"v.","meaning":"表达；传达"}]'::jsonb,
   '表达；传达', '表达；传达',
   'Her calm voice conveyed confidence.', '她平静的声音传达出自信。', 7),
  ('thrive', 'thrive', 'θraɪv', '[{"partOfSpeech":"v.","meaning":"茁壮成长；兴旺"}]'::jsonb,
   '茁壮成长；兴旺', '茁壮成长；兴旺',
   'People thrive when they feel trusted.', '人们在被信任时更容易蓬勃成长。', 8)
on conflict (term) do nothing;

-- 拷贝逻辑单独成函数，注册触发器和「手动补发」都能调，不必两处维护同一段 SQL。
-- security definer：调用方是刚建出来的用户（甚至还没有 auth.uid()），要绕过 words
-- 的 owner 策略写入。
create or replace function public.grant_starter_words(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with inserted as (
    insert into public.words (
      user_id, term, normalized_term, lemma, phonetic, parts,
      primary_meaning, contextual_meaning, example_en, example_zh,
      first_context, first_source_title, status, created_at
    )
    select
      p_user_id, s.term, lower(trim(s.term)), s.lemma, s.phonetic, s.parts,
      s.primary_meaning, s.contextual_meaning, s.example_en, s.example_zh,
      -- 例句同时当作首次语境，词详情页和练习的填空题都从这里取。
      s.example_en, '词鲸新手词库', 'new',
      -- 按 sort_order 拉开 created_at，让词库列表（按 created_at desc）的顺序稳定，
      -- 而不是 8 个词共用同一个时间戳后顺序随机。
      now() + make_interval(secs => s.sort_order)
    from public.starter_words s
    where s.is_active
    order by s.sort_order
    on conflict (user_id, normalized_term) do nothing
    returning id, first_context, contextual_meaning, first_source_title
  ), contexts as (
    insert into public.word_contexts (user_id, word_id, context_text, contextual_meaning, sentence, source_title)
    select p_user_id, i.id, i.first_context, i.contextual_meaning, i.first_context, i.first_source_title
    from inserted i where i.first_context is not null
    returning 1
  )
  select count(*) into v_count from inserted;

  return v_count;
end;
$$;

revoke execute on function public.grant_starter_words(uuid) from public, anon, authenticated;

-- 注册触发器接上这一步。
--
-- **关键：整段拷贝包在 exception 里**。这个函数跑在 auth.users 的 insert 事务里，
-- 任何未捕获的异常都会让整条注册失败——「送几个词」这种锦上添花的事绝不能有把
-- 注册搞挂的可能。种子表被清空、某个词违反了 words 的 check 约束、将来给 words
-- 加了新的 not null 列忘了同步这里，都属于这一类：宁可这个新用户拿不到词（还能
-- 走设置里的手动导入兜底），也不能让他注册不了。
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;

  begin
    perform public.grant_starter_words(new.id);
  exception when others then
    raise warning 'grant_starter_words failed for %: %', new.id, sqlerrm;
  end;

  return new;
end;
$$;
