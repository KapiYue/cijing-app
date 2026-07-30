import path from "node:path";
import { fileURLToPath } from "node:url";
import { readEnvFile } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const config = readEnvFile(path.join(root, ".env"));
const baseURL = config.SUPABASE_URL?.replace(/\/$/, "");
const secretKey = config.SUPABASE_SECRET_KEY;
const emailArgument = process.argv.find((value) => value.startsWith("--email="));
const email = (emailArgument?.slice("--email=".length) || "superai@qq.com").trim().toLowerCase();
const shouldApply = process.argv.includes("--apply");

if (!baseURL || !secretKey) throw new Error(".env 中缺少 SUPABASE_URL 或 SUPABASE_SECRET_KEY");

async function request(apiPath, { method = "GET", body, headers = {} } = {}) {
  const response = await fetch(`${baseURL}${apiPath}`, {
    method,
    headers: {
      apikey: secretKey,
      Authorization: `Bearer ${secretKey}`,
      "Content-Type": "application/json",
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (response.status === 204) return null;
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(`${apiPath}: HTTP ${response.status} ${JSON.stringify(payload)?.slice(0, 500)}`);
  }
  return payload;
}

async function findUser(targetEmail) {
  const perPage = 1000;
  for (let page = 1; page <= 10; page += 1) {
    const payload = await request(`/auth/v1/admin/users?page=${page}&per_page=${perPage}`);
    const users = payload?.users ?? [];
    const match = users.find((user) => user.email?.toLowerCase() === targetEmail);
    if (match) return match;
    if (users.length < perPage) break;
  }
  throw new Error(`未找到审核账号：${targetEmail}`);
}

const sourceTitle = "Chrome 扩展";
const now = Date.now();
const isoDaysAgo = (days, hour = 9) => {
  const date = new Date(now - days * 86_400_000);
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
};

const vocabulary = [
  {
    term: "estimate", phonetic: "ˈestɪmeɪt", part: "v.", meaning: "估计；估算",
    definition: "To form an approximate judgment or calculation.",
    example: "Mei stopped trying to estimate how quickly her English would improve.", exampleZh: "小梅不再估算英语能多快进步。",
    status: "weak", strength: 0.15, intervalDays: 1, repetitions: 1, lapses: 2, errorCount: 2,
  },
  {
    term: "investment", phonetic: "ɪnˈvestmənt", part: "n.", meaning: "投资；投入",
    definition: "The use of time, effort, or money for a future benefit.",
    example: "This routine became an investment in her future.", exampleZh: "这个习惯成了她对未来的投入。",
    status: "weak", strength: 0.33, intervalDays: 1, repetitions: 1, lapses: 2, errorCount: 2,
  },
  {
    term: "independent", phonetic: "ˌɪndɪˈpendənt", part: "adj.", meaning: "独立的；自主的",
    definition: "Able to act or develop without depending on others.",
    example: "This independent routine became part of her day.", exampleZh: "这个独立的习惯成了她每天生活的一部分。",
    status: "learning", strength: 0.45, intervalDays: 2, repetitions: 2, lapses: 0, errorCount: 0,
  },
  {
    term: "outperform", phonetic: "ˌaʊtpərˈfɔːrm", part: "v.", meaning: "胜过；表现优于",
    definition: "To perform better than someone or something else.",
    example: "Small daily efforts can outperform sudden bursts of motivation.", exampleZh: "每天微小的努力能够胜过一时的热情。",
    status: "review", strength: 0.33, intervalDays: 3, repetitions: 2, lapses: 0, errorCount: 0,
  },
  {
    term: "automated", phonetic: "ˈɔːtəmeɪtɪd", part: "adj.", meaning: "自动化的",
    definition: "Controlled or performed automatically by a system.",
    example: "Automated reminders helped her maintain the routine.", exampleZh: "自动提醒帮助她维持这个习惯。",
    status: "learning", strength: 0.52, intervalDays: 2, repetitions: 2, lapses: 0, errorCount: 0,
  },
  {
    term: "alternative", phonetic: "ɔːlˈtɜːrnətɪv", part: "n.", meaning: "选择；替代方案",
    definition: "One of two or more available possibilities.",
    example: "She chose a sustainable alternative to cramming.", exampleZh: "她选择了可持续的学习方式来代替突击。",
    status: "learning", strength: 0.41, intervalDays: 2, repetitions: 2, lapses: 0, errorCount: 0,
  },
  {
    term: "defense", phonetic: "dɪˈfens", part: "n.", meaning: "防御；保护",
    definition: "The act of protecting someone, something, or an idea.",
    example: "Clearer words gave her a stronger defense of her ideas.", exampleZh: "更清晰的词语让她能更有力地表达和捍卫观点。",
    status: "review", strength: 0.38, intervalDays: 3, repetitions: 2, lapses: 0, errorCount: 0,
  },
  {
    term: "long-horizon", phonetic: "ˌlɔːŋ həˈraɪzn", part: "adj.", meaning: "长期的；远期的",
    definition: "Focused on results or decisions over a long period.",
    example: "She developed a long-horizon perspective on learning.", exampleZh: "她形成了看待学习的长期视角。",
    status: "new", strength: 0.08, intervalDays: 0, repetitions: 0, lapses: 0, errorCount: 0,
  },
];

function wordRow(userID, item, index) {
  const createdAt = isoDaysAgo(8 - index, 8 + (index % 3));
  const masteredAt = item.status === "mastered" ? isoDaysAgo(1, 20) : null;
  return {
    user_id: userID,
    term: item.term,
    normalized_term: item.term,
    lemma: item.term,
    phonetic: item.phonetic,
    audio_url: null,
    parts: [{ part_of_speech: item.part, meaning: item.meaning }],
    primary_meaning: item.meaning,
    contextual_meaning: item.meaning,
    english_definition: item.definition,
    example_en: item.example,
    example_zh: item.exampleZh,
    first_context: item.example,
    first_source_url: null,
    first_source_title: sourceTitle,
    notes: "App Store 商品页截图审核演示词集",
    custom_meaning: null,
    status: item.status,
    strength: item.strength,
    ease_factor: 2.5,
    interval_days: item.intervalDays,
    repetitions: item.repetitions,
    lapses: item.lapses,
    lookup_count: 2 + index,
    error_count: item.errorCount,
    due_at: item.status === "new" ? isoDaysAgo(0) : isoDaysAgo(1),
    last_reviewed_at: item.repetitions > 0 ? isoDaysAgo(1, 19) : null,
    mastered_at: masteredAt,
    created_at: createdAt,
    updated_at: isoDaysAgo(0, 10),
  };
}

function activityRows(userID) {
  return Array.from({ length: 18 }, (_, offset) => {
    const date = new Date(now - offset * 86_400_000);
    const activityDate = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
    return {
      user_id: userID,
      activity_date: activityDate,
      learned_count: 5 + (offset % 5),
      reviewed_count: 14 + (offset % 8),
      reading_count: offset % 3 === 0 ? 2 : 1,
      practice_count: 8 + (offset % 7),
      minutes: 18 + (offset % 6) * 4,
      completed: true,
      updated_at: isoDaysAgo(offset, 21),
    };
  });
}

const user = await findUser(email);
const [existingWords, existingReadings, existingProfiles, existingActivity] = await Promise.all([
  request(`/rest/v1/words?user_id=eq.${user.id}&select=id,normalized_term,status,strength&order=created_at.asc`),
  request(`/rest/v1/reading_sessions?user_id=eq.${user.id}&select=id,title,target_terms,paragraphs,created_at&order=created_at.desc`),
  request(`/rest/v1/profiles?id=eq.${user.id}&select=display_name,daily_new_goal,daily_review_goal,preferred_difficulty,preferred_theme,preferred_style,timezone&limit=1`),
  request(`/rest/v1/daily_activity?user_id=eq.${user.id}&select=activity_date,learned_count,reviewed_count,reading_count,practice_count,completed&order=activity_date.desc`),
]);

const expectedStatuses = new Map(vocabulary.map((item) => [item.term, item.status]));
const expectedReadingTitles = ["A Quiet Kind of Progress", "The Train Beyond the Rain", "Designing Time for Deep Work"];
const wordsMatch = existingWords.length === vocabulary.length
  && existingWords.every((word) => expectedStatuses.get(word.normalized_term) === word.status);
const readingsMatch = existingReadings.length === expectedReadingTitles.length
  && expectedReadingTitles.every((title) => existingReadings.some((reading) => reading.title === title));
const profileMatches = existingProfiles[0]?.display_name === "Qing"
  && existingProfiles[0]?.daily_new_goal === 8
  && existingProfiles[0]?.daily_review_goal === 20
  && existingProfiles[0]?.preferred_difficulty === "intermediate"
  && existingProfiles[0]?.preferred_theme === "daily_life"
  && existingProfiles[0]?.preferred_style === "story"
  && existingProfiles[0]?.timezone === "Asia/Shanghai";
const activityMatches = existingActivity.length === 18
  && existingActivity.every((activity) => activity.completed);

if (!shouldApply) {
  console.log(JSON.stringify({
    mode: "check",
    email,
    existingWords: existingWords.length,
    expectedWords: vocabulary.length,
    existingReadings: existingReadings.map((reading) => reading.title),
    expectedReadings: expectedReadingTitles,
    activityDays: existingActivity.length,
    profileDisplayName: existingProfiles[0]?.display_name ?? null,
    screenshotCoreDatasetMatches: wordsMatch && readingsMatch && profileMatches && activityMatches,
    previewOnlyTotals: "商品页截图中的 146/68 与首页 8 个新词是 -ui-preview 独立汇总值，不能由同一套 8 词生产数据同时推导。",
    nextStep: `node scripts/ensure-review-data.mjs --email=${email} --apply`,
  }, null, 2));
  process.exit(0);
}

await Promise.all([
  request(`/rest/v1/reading_sessions?user_id=eq.${user.id}`, { method: "DELETE" }),
  request(`/rest/v1/daily_activity?user_id=eq.${user.id}`, { method: "DELETE" }),
]);
await request(`/rest/v1/words?user_id=eq.${user.id}`, { method: "DELETE" });
await request(`/rest/v1/profiles?id=eq.${user.id}`, {
  method: "PATCH",
  body: {
    display_name: "Qing",
    daily_new_goal: 8,
    daily_review_goal: 20,
    preferred_difficulty: "intermediate",
    preferred_theme: "daily_life",
    preferred_style: "story",
    timezone: "Asia/Shanghai",
  },
  headers: { Prefer: "return=minimal" },
});

const savedWords = await request("/rest/v1/words?on_conflict=user_id,normalized_term", {
  method: "POST",
  body: vocabulary.map((item, index) => wordRow(user.id, item, index)),
  headers: { Prefer: "resolution=merge-duplicates,return=representation" },
});

const wordsByTerm = new Map(savedWords.map((word) => [word.normalized_term, word]));
const targetWordIDs = vocabulary.map((item) => wordsByTerm.get(item.term)?.id).filter(Boolean);
const readingRows = [
  {
    user_id: user.id,
    title: "A Quiet Kind of Progress",
    subtitle: "一种安静的进步",
    theme: "daily_life",
    style: "story",
    difficulty: "intermediate",
    target_word_ids: targetWordIDs,
    target_terms: vocabulary.map((item) => item.term),
    paragraphs: [
      {
        english: "Small daily efforts can outperform sudden bursts of motivation. Mei stopped trying to estimate how quickly her English would improve and focused on one thoughtful page each morning.",
        chinese: "每天微小的努力能够胜过一时的热情。小梅不再估算英语能多快进步，而是专注于每天清晨认真读完一页。",
      },
      {
        english: "This independent routine became an investment in her future. Automated reminders helped, but the real change came from choosing a sustainable alternative to cramming.",
        chinese: "这个独立的习惯成了她对未来的投资。自动提醒有所帮助，但真正的改变来自她选择了可持续的学习方式，而不是突击。",
      },
      {
        english: "Weeks later, she could defend her ideas with clearer words and a long-horizon perspective. Her progress was quiet, but unmistakable.",
        chinese: "几周后，她能用更清晰的词语表达并捍卫自己的观点，也拥有了更长远的视角。她的进步很安静，却清晰可见。",
      },
    ],
    estimated_minutes: 4,
    cache_key: "app-review-screenshot-v2-home",
    is_cached: true,
    translations_visible: true,
    completed_at: isoDaysAgo(0, 20),
    created_at: isoDaysAgo(0, 9),
  },
  {
    user_id: user.id,
    title: "The Train Beyond the Rain",
    subtitle: "驶出雨幕的列车",
    theme: "travel",
    style: "story",
    difficulty: "upper_intermediate",
    target_word_ids: targetWordIDs.slice(0, 6),
    target_terms: vocabulary.slice(0, 6).map((item) => item.term),
    paragraphs: [{
      english: "A delayed train gave Lina an unexpected afternoon in a mountain town. Instead of treating it as wasted time, she wandered into a family café and listened to the stories around her.",
      chinese: "晚点的列车让莉娜意外地在山城多停留了一个下午。她没有把这当作浪费，而是走进一家家庭咖啡馆，倾听身边的故事。",
    }],
    estimated_minutes: 5,
    cache_key: "app-review-screenshot-v2-travel",
    is_cached: true,
    translations_visible: false,
    completed_at: isoDaysAgo(1, 20),
    created_at: isoDaysAgo(1, 9),
  },
  {
    user_id: user.id,
    title: "Designing Time for Deep Work",
    subtitle: "为深度工作设计时间",
    theme: "workplace",
    style: "article",
    difficulty: "advanced",
    target_word_ids: targetWordIDs.slice(-5),
    target_terms: vocabulary.slice(-5).map((item) => item.term),
    paragraphs: [{
      english: "Protecting attention is less about perfect discipline than deliberate design. A team can reduce interruptions by agreeing on quiet hours and making communication expectations explicit.",
      chinese: "保护注意力与其说依赖完美的自律，不如说依赖有意识的设计。团队可以约定安静时段，并明确沟通预期，以减少干扰。",
    }],
    estimated_minutes: 6,
    cache_key: "app-review-screenshot-v2-work",
    is_cached: true,
    translations_visible: false,
    completed_at: isoDaysAgo(2, 20),
    created_at: isoDaysAgo(2, 9),
  },
];

const savedReadings = await request("/rest/v1/reading_sessions", {
  method: "POST",
  body: readingRows,
  headers: { Prefer: "return=representation" },
});

await request("/rest/v1/daily_activity?on_conflict=user_id,activity_date", {
  method: "POST",
  body: activityRows(user.id),
  headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
});

const verification = await Promise.all([
  request(`/rest/v1/words?user_id=eq.${user.id}&select=id,normalized_term,status,strength&order=created_at.asc`),
  request(`/rest/v1/reading_sessions?user_id=eq.${user.id}&select=id,title,target_terms,paragraphs,completed_at&order=created_at.desc`),
  request(`/rest/v1/daily_activity?user_id=eq.${user.id}&select=activity_date,learned_count,reviewed_count,reading_count,practice_count,minutes,completed&order=activity_date.desc`),
  request(`/rest/v1/profiles?id=eq.${user.id}&select=display_name,daily_new_goal,daily_review_goal,preferred_difficulty,preferred_theme,preferred_style,timezone&limit=1`),
]);

console.log(JSON.stringify({
  status: "ok",
  email,
  words: verification[0].length,
  reviewVocabulary: verification[0].map((word) => `${word.normalized_term}:${word.status}`),
  reviewReadings: savedReadings.map((reading) => ({ title: reading.title, paragraphs: reading.paragraphs.length })),
  activityDays: verification[2].length,
  recentSevenTotals: verification[2].slice(0, 7).reverse().map((day) => day.learned_count + day.reviewed_count + day.practice_count),
  profile: verification[3][0],
  screenshotCoreDatasetMatches: verification[0].length === 8
    && verification[1].length === 3
    && verification[2].length === 18
    && verification[3][0]?.display_name === "Qing",
  previewOnlyTotals: "146/68 与首页 8 个新词属于 -ui-preview 独立汇总值；生产 RPC 会按当前 8 词真实计算为 8/0 与 1 个新词。",
}, null, 2));
