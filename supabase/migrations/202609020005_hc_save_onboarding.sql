-- 首启结果的服务端落点。`design.md` §5.3（S1–S3）· §11 ④ · dev-todo T2。
--
-- 为什么必须有这个文件：`hc_profiles` 的 RLS 是开的，但 **`wx.request` 没有 `PATCH`**
-- （`design.md` §11 ③），而 PostgREST 的更新只走 `PATCH /rest/v1/<table>` ——
-- 小程序**物理上写不了任何表**，`0004` 的四个 RPC 也没有一个能写 profile。
-- 于是首启结果只能落本地，换设备就没了。本文件补上唯一那条写入路径。
--
-- 落点裁决（§12.1 T7「共享 schema 只放事实，不放解释」）：
--   level_line / scenes / onboarding_done_at   → hc_profiles（解释）
--   播种的 20 个词                              → public.words（事实）
--
-- 播种落 `words` 而不是 `hc_` 私有表，理由是**它本来就没有第二种选法**：
--   ① SM-2 的全部状态（ease_factor / interval_days / repetitions / due_at）在 words 上，
--      `apply_review` 的入参是 `words.id`，`hc_word_status` 的外键也是 `words.id`。
--      落私有表 = 把整套调度和激活判据再实现一遍。
--   ② `0004` 的 `hc_get_study_queue` 已经写死了「capture_rank = 1 → 无原句的底座词」这一档，
--      它从一开始就假设底座词在 `words` 里。
--   ③ 「这个用户要学这个词」是**事实**，不是解释；解释是 level_line 和队列优先级。
--   ④ 走「我有词鲸账号」的老用户**跳过 S1–S3**（§5.3 S0），永远不会跑到这个函数，
--      所以不存在往已有账号里灌数据的情况。被播种的只有 words 恒为空的微信新用户。
--
-- 「首启添加」那行来源文案**不写进共享表**（它是解释）。客户端按「无 first_context
-- 且无 first_source_url/title」推导即可。⚠️ T4 查词页往 `save_word` 写词时必须带上
-- `source_title`，否则它也会被推导成「首启添加」。

-- ─────────────────────────────────────────────────────────────
-- hc_base_words：4,400 词底座的**服务端**副本（全局只读，与 starter_words 同构）
--
-- 客户端主包里的 `assets/base-words.json` 只有 spelling + band + frq（§13.1 定的
-- 「不存释义」是为了守住主包 90KB 预算），**服务端没有这个预算**。
-- 而 `words.primary_meaning` 是 NOT NULL —— 播种必须在某处拿到释义，
-- 否则新用户第一轮学习的 20 张卡片全是「待补充」。这张表就是那个某处。
--
-- 灌数据是**另一件事**（dev-todo T2 的导入脚本，从 ecdict.csv 抽 phonetic + 释义）。
-- 表空着的时候 hc_save_onboarding 会退化成写「待补充」，不会失败 —— 迁移可以先跑。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.hc_base_words (
  -- 一律小写，与 words.normalized_term 同口径，join 才对得上
  spelling        text primary key,
  band            smallint not null check (band between 1 and 6),
  -- 位与：1 = NGSL，2 = BSL（与 packs/base.json 的第 3 列同义）
  source_bits     smallint not null default 0,
  -- ECDICT frq 排名，越小越常见。**0 = 缺值，排序时一律当作最后**
  frq_rank        integer not null default 0,
  phonetic        text,
  primary_meaning text,
  updated_at      timestamptz not null default now()
);

create index if not exists hc_base_words_band_frq_idx
  on public.hc_base_words (band, frq_rank);

alter table public.hc_base_words enable row level security;

-- 全局共享的只读词表：登录用户都能读（S2 抽样要走 RPC 读它），谁都不能写。
-- 维护走导入脚本 / service_role。anon 不授予任何权限。
drop policy if exists hc_base_words_read on public.hc_base_words;
create policy hc_base_words_read on public.hc_base_words
  for select using (auth.role() = 'authenticated');

grant select on public.hc_base_words to authenticated;

-- 导入脚本（`packages/db/scripts/import-base-words.mjs`）拿 service_role 直连 PostgREST
-- 写这张表，所以写权限必须显式 grant —— 理由同 0003 结尾那段：托管项目建表时拿到过
-- 历史默认权限，生产「碰巧能写」，但 `supabase db reset` 重建出来的库里 service_role
-- 只有 REFERENCES/TRIGGER/TRUNCATE，灌词当场 403。
-- service_role 本来就绕过 RLS，这里只是把门开到 RLS 面前，不放宽任何边界。
grant select, insert, update on public.hc_base_words to service_role;

-- ─────────────────────────────────────────────────────────────
-- hc_save_onboarding：一个事务里落完首启的全部结果
--
--   1. hc_profiles ← level_line / scenes / onboarding_done_at
--   2. 词鲸送的 8 个新手词 → status = 'ignored'
--   3. 播种词 → 该用户的 words 行
--
-- security invoker：RLS 照旧生效，用户只能写自己的行。不需要 definer——
-- 它写的每一张表 authenticated 都已有 owner-only 策略。
-- ─────────────────────────────────────────────────────────────
create or replace function public.hc_save_onboarding(
  p_scenes     text[] default '{}',
  p_level_line integer default null,
  p_seed_terms text[] default '{}'
)
returns jsonb
language plpgsql
security invoker
set search_path = public
set timezone = 'Asia/Shanghai'
as $$
declare
  v_uid       uuid := auth.uid();
  v_first_run boolean;
  v_done_at   timestamptz;
  v_seeded    integer := 0;
  v_ignored   integer := 0;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_level_line is not null and p_level_line not between 1 and 6 then
    raise exception 'level_line 必须是 1–6 的频段序号，收到 %', p_level_line;
  end if;

  -- 幂等的判据是 onboarding_done_at，不是「有没有 hc_profiles 行」。
  -- 重复调用（离线补发、用户返回上一步再点一次）只刷新 level_line / scenes，
  -- **不再播种第二批 20 个词**，也不再动新手词。
  select onboarding_done_at into v_done_at
  from public.hc_profiles where user_id = v_uid;
  v_first_run := v_done_at is null;

  insert into public.hc_profiles (user_id, level_line, scenes, onboarding_done_at, updated_at)
  values (v_uid, p_level_line::smallint, coalesce(p_scenes, '{}'), now(), now())
  on conflict (user_id) do update set
    level_line         = coalesce(excluded.level_line, hc_profiles.level_line),
    scenes             = excluded.scenes,
    -- 已经做完过就保留原时间戳，别把「第一次做完首启是什么时候」擦掉
    onboarding_done_at = coalesce(hc_profiles.onboarding_done_at, excluded.onboarding_done_at),
    updated_at         = now()
  returning onboarding_done_at into v_done_at;

  if v_first_run then
    -- 词鲸的 handle_new_user 触发器会给每个新注册用户送 8 个新手词
    -- （`cijing/.../202608210001_starter_words.sql`）。它们的 created_at 早于播种词，
    -- 而 hc_get_study_queue 的新词档按 created_at 升序 —— 不处理的话，用户走完
    -- 40 秒首启后，第一轮学的是 resilient / subtle / navigate，**不是他刚勾的词**，
    -- 「我的生词」里还会露出另一个产品的品牌名「词鲸新手词库」。
    --
    -- 用 'ignored' 而不是删行：§12.4 第 2 条不做硬删除，
    -- 且 review_events.word_id 是 ON DELETE CASCADE，删词会连坐删掉复习史。
    -- 只动**一次都没复习过**的，用户真学过就不碰。
    update public.words
       set status = 'ignored'
     where user_id = v_uid
       and status = 'new'
       and repetitions = 0
       and last_reviewed_at is null
       and first_source_title = '词鲸新手词库';
    get diagnostics v_ignored = row_count;

    with seeds as (
      select lower(trim(t.term)) as norm, trim(t.term) as term, t.ord
      from unnest(coalesce(p_seed_terms, '{}')) with ordinality as t(term, ord)
      where nullif(trim(t.term), '') is not null
    ),
    -- 客户端理论上不会送重复词，但 on conflict 只挡库里已有的，挡不住同一批里的重复
    deduped as (
      select distinct on (norm) norm, term, ord from seeds order by norm, ord
    ),
    ins as (
      insert into public.words (
        user_id, term, normalized_term, lemma, phonetic, primary_meaning, status, created_at
      )
      select
        v_uid, d.term, d.norm, d.norm,
        b.phonetic,
        -- 底座表还没灌数据时退化成「待补充」，不让迁移与导入互相阻塞
        coalesce(nullif(b.primary_meaning, ''), '待补充'),
        'new',
        -- 按 ord 拉开 created_at：客户端送来的顺序就是 frq 升序（§5.3 S3 的播种规则），
        -- 而今日队列的新词档按 created_at 升序取 —— 共用一个时间戳顺序就随机了
        now() + make_interval(secs => d.ord::integer)
      from deduped d
      left join public.hc_base_words b on b.spelling = d.norm
      order by d.ord
      on conflict (user_id, normalized_term) do nothing
      returning 1
    )
    select count(*) into v_seeded from ins;
  end if;

  return jsonb_build_object(
    'first_run',             v_first_run,
    'level_line',            p_level_line,
    'seeded_count',          v_seeded,
    'ignored_starter_count', v_ignored,
    'onboarding_done_at',    v_done_at
  );
end;
$$;

revoke execute on function public.hc_save_onboarding(text[], integer, text[]) from public, anon;
grant execute on function public.hc_save_onboarding(text[], integer, text[]) to authenticated;
