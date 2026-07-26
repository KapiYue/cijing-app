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

const sourceTitle = "词鲸 · 持续进步主题词集";
const now = Date.now();
const isoDaysAgo = (days, hour = 9) => {
  const date = new Date(now - days * 86_400_000);
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
};

const vocabulary = [
  {
    term: "resilient", phonetic: "rɪˈzɪliənt", part: "adj.", meaning: "有韧性的；能够恢复的",
    definition: "Able to recover and continue after difficulty.",
    example: "A resilient learner treats mistakes as useful information.", exampleZh: "有韧性的学习者会把错误视为有用的信息。",
    status: "learning", strength: 0.54, intervalDays: 3, repetitions: 2, lapses: 0, errorCount: 1,
  },
  {
    term: "deliberate", phonetic: "dɪˈlɪbərət", part: "adj.", meaning: "有意识的；深思熟虑的",
    definition: "Done consciously and with careful intention.",
    example: "She made a deliberate choice to study for twenty minutes each morning.", exampleZh: "她有意识地选择每天早晨学习二十分钟。",
    status: "review", strength: 0.66, intervalDays: 5, repetitions: 3, lapses: 0, errorCount: 0,
  },
  {
    term: "sustain", phonetic: "səˈsteɪn", part: "v.", meaning: "维持；支撑",
    definition: "To keep an activity or process continuing over time.",
    example: "Small goals are easier to sustain than sudden bursts of effort.", exampleZh: "小目标比突发式努力更容易长期维持。",
    status: "weak", strength: 0.29, intervalDays: 1, repetitions: 1, lapses: 2, errorCount: 2,
  },
  {
    term: "subtle", phonetic: "ˈsʌtl", part: "adj.", meaning: "细微的；不易察觉的",
    definition: "Small but meaningful and not immediately obvious.",
    example: "A subtle improvement appeared in her pronunciation after a week.", exampleZh: "一周后，她的发音出现了细微的进步。",
    status: "new", strength: 0.12, intervalDays: 0, repetitions: 0, lapses: 0, errorCount: 0,
  },
  {
    term: "consistent", phonetic: "kənˈsɪstənt", part: "adj.", meaning: "持续稳定的；一致的",
    definition: "Continuing in a steady and reliable way.",
    example: "Consistent practice made difficult sentences feel familiar.", exampleZh: "持续稳定的练习让困难的句子逐渐变得熟悉。",
    status: "learning", strength: 0.48, intervalDays: 2, repetitions: 2, lapses: 0, errorCount: 1,
  },
  {
    term: "reflect", phonetic: "rɪˈflekt", part: "v.", meaning: "反思；认真思考",
    definition: "To think carefully about an experience or decision.",
    example: "At night, he took a minute to reflect on what he had learned.", exampleZh: "晚上，他会花一分钟反思当天学到的内容。",
    status: "mastered", strength: 0.91, intervalDays: 21, repetitions: 6, lapses: 0, errorCount: 0,
  },
  {
    term: "progress", phonetic: "ˈprɑːɡres", part: "n.", meaning: "进步；进展",
    definition: "Movement toward a better or more complete state.",
    example: "Visible progress often grows from work that first feels ordinary.", exampleZh: "看得见的进步往往来自起初看似普通的努力。",
    status: "review", strength: 0.71, intervalDays: 7, repetitions: 4, lapses: 0, errorCount: 0,
  },
  {
    term: "momentum", phonetic: "moʊˈmentəm", part: "n.", meaning: "动力；势头",
    definition: "The force that keeps a process developing after it has begun.",
    example: "Completing one short lesson gave her momentum for the next day.", exampleZh: "完成一节短课让她有了第二天继续学习的动力。",
    status: "new", strength: 0.16, intervalDays: 0, repetitions: 0, lapses: 0, errorCount: 0,
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
    notes: "App Store 审核演示词集",
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
  const values = [
    [5, 8, 1, 4, 22], [3, 10, 1, 5, 25], [4, 7, 1, 4, 19], [2, 12, 2, 6, 31],
    [3, 9, 1, 5, 24], [2, 6, 1, 3, 17], [1, 5, 1, 4, 18],
  ];
  return values.map(([learned, reviewed, reading, practice, minutes], index) => {
    const date = new Date(now - (6 - index) * 86_400_000);
    const activityDate = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
    return {
      user_id: userID,
      activity_date: activityDate,
      learned_count: learned,
      reviewed_count: reviewed,
      reading_count: reading,
      practice_count: practice,
      minutes,
      completed: true,
      updated_at: isoDaysAgo(6 - index, 21),
    };
  });
}

const user = await findUser(email);
const existingWords = await request(`/rest/v1/words?user_id=eq.${user.id}&select=id,normalized_term,status`);
const existingReadings = await request(`/rest/v1/reading_sessions?user_id=eq.${user.id}&cache_key=eq.app-review-demo-v1&select=id,title,created_at&limit=1`);

if (!shouldApply) {
  console.log(JSON.stringify({
    mode: "check",
    email,
    existingWords: existingWords.length,
    existingReviewVocabulary: existingWords.filter((word) => vocabulary.some((item) => item.term === word.normalized_term)).length,
    existingReviewReading: existingReadings[0]?.title ?? null,
    nextStep: `node scripts/ensure-review-data.mjs --email=${email} --apply`,
  }, null, 2));
  process.exit(0);
}

const savedWords = await request("/rest/v1/words?on_conflict=user_id,normalized_term", {
  method: "POST",
  body: vocabulary.map((item, index) => wordRow(user.id, item, index)),
  headers: { Prefer: "resolution=merge-duplicates,return=representation" },
});

const wordsByTerm = new Map(savedWords.map((word) => [word.normalized_term, word]));
const targetWordIDs = vocabulary.map((item) => wordsByTerm.get(item.term)?.id).filter(Boolean);
const reading = {
  user_id: user.id,
  title: "The Garden of Steady Progress",
  subtitle: "持续进步的花园",
  theme: "daily_life",
  style: "story",
  difficulty: "intermediate",
  target_word_ids: targetWordIDs,
  target_terms: vocabulary.map((item) => item.term),
  paragraphs: [
    {
      english: "Every morning, Lina made a deliberate plan to study for twenty quiet minutes. Her consistent routine felt small, but each page showed a little more progress.",
      chinese: "每天早晨，莉娜都会有意识地安排二十分钟安静学习。她稳定的习惯看似微小，但每一页都能看见一点进步。",
    },
    {
      english: "When a subtle mistake appeared, she did not feel defeated. She paused to reflect, corrected the sentence, and became more resilient each time.",
      chinese: "当细微的错误出现时，她没有感到挫败。她停下来反思、改正句子，并在每一次练习中变得更有韧性。",
    },
    {
      english: "After several weeks, the habit was easy to sustain. The momentum from one completed lesson carried naturally into the next, like a garden growing one leaf at a time.",
      chinese: "几周后，这个习惯已经很容易坚持。完成一节课积累的动力自然延续到下一节，就像花园一次长出一片新叶。",
    },
  ],
  estimated_minutes: 4,
  cache_key: "app-review-demo-v1",
  is_cached: true,
  translations_visible: false,
  completed_at: isoDaysAgo(1, 20),
  created_at: isoDaysAgo(2, 9),
};

let savedReading;
if (existingReadings[0]) {
  const rows = await request(`/rest/v1/reading_sessions?id=eq.${existingReadings[0].id}`, {
    method: "PATCH",
    body: reading,
    headers: { Prefer: "return=representation" },
  });
  savedReading = rows[0];
} else {
  const rows = await request("/rest/v1/reading_sessions", {
    method: "POST",
    body: reading,
    headers: { Prefer: "return=representation" },
  });
  savedReading = rows[0];
}

await request("/rest/v1/daily_activity?on_conflict=user_id,activity_date", {
  method: "POST",
  body: activityRows(user.id),
  headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
});

const verification = await Promise.all([
  request(`/rest/v1/words?user_id=eq.${user.id}&select=id,normalized_term,status&order=created_at.asc`),
  request(`/rest/v1/reading_sessions?user_id=eq.${user.id}&select=id,title,target_terms,paragraphs,completed_at&order=created_at.desc`),
  request(`/rest/v1/daily_activity?user_id=eq.${user.id}&select=activity_date,reviewed_count,reading_count,minutes&order=activity_date.desc&limit=7`),
]);

console.log(JSON.stringify({
  status: "ok",
  email,
  words: verification[0].length,
  reviewVocabulary: verification[0].filter((word) => vocabulary.some((item) => item.term === word.normalized_term)).map((word) => word.normalized_term),
  reviewReading: {
    id: savedReading.id,
    title: savedReading.title,
    paragraphs: savedReading.paragraphs.length,
    completedAt: savedReading.completed_at,
  },
  activityDays: verification[2].length,
}, null, 2));
