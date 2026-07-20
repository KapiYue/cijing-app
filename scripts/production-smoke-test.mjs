import path from "node:path";
import { fileURLToPath } from "node:url";
import { readEnvFile } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const config = readEnvFile(path.join(root, ".env"));
const baseURL = config.SUPABASE_URL?.replace(/\/$/, "");
const publishableKey = config.SUPABASE_PUBLISHABLE_KEY || config.SUPABASE_ANON_KEY;
const secretKey = config.SUPABASE_SECRET_KEY;
if (!baseURL || !publishableKey || !secretKey) throw new Error("生产验收缺少 Supabase 环境变量");

const runID = Date.now();
const adminBootstrap = process.argv.includes("--admin-bootstrap");
const email = adminBootstrap ? `cijing-e2e-${runID}@cijing.app` : process.env.CIJING_E2E_EMAIL;
if (!email) throw new Error("公开注册验收需要 CIJING_E2E_EMAIL；仅验证登录与内部功能可使用 --admin-bootstrap");
const password = `CiJing-E2E-${runID}!`;
let userID;

async function request(apiPath, { method = "GET", body, token, admin = false, headers = {} } = {}) {
  const apiKey = admin ? secretKey : publishableKey;
  const response = await fetch(`${baseURL}${apiPath}`, {
    method,
    headers: {
      apikey: apiKey,
      Authorization: `Bearer ${token || apiKey}`,
      "Content-Type": "application/json",
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${apiPath}: HTTP ${response.status} ${JSON.stringify(payload)?.slice(0, 500)}`);
  return payload;
}

function wordPayload(term, meaning, sentence) {
  return {
    term, lemma: term, phonetic: null,
    parts: [{ part_of_speech: "adj.", meaning }],
    primary_meaning: meaning, contextual_meaning: meaning,
    english_definition: null, example_en: sentence, example_zh: null,
    context: sentence, sentence, source_url: null,
    source_title: `词鲸背单词 E2E ${runID}`,
  };
}

try {
  if (adminBootstrap) {
    const created = await request("/auth/v1/admin/users", {
      method: "POST", admin: true, body: { email, password, email_confirm: true },
    });
    userID = created.id;
  } else {
    const signup = await request("/auth/v1/signup", { method: "POST", body: { email, password } });
    userID = signup.user?.id;
    if (!userID) throw new Error("注册未返回用户 ID");
    if (signup.access_token) throw new Error("生产邮箱确认策略未生效");
    await request(`/auth/v1/admin/users/${userID}`, {
      method: "PUT", admin: true, body: { email_confirm: true },
    });
  }
  const session = await request("/auth/v1/token?grant_type=password", {
    method: "POST", body: { email, password },
  });
  const token = session.access_token;
  if (!token) throw new Error("邮箱确认后仍无法登录");

  const profileRows = await request("/rest/v1/profiles?select=*", { token });
  if (profileRows.length !== 1 || profileRows[0].id !== userID) throw new Error("注册未自动创建 profile");

  const inputs = [
    wordPayload("resilient", "有韧性的", "The resilient learner returned to the lesson after a difficult day."),
    wordPayload("subtle", "微妙的", "A subtle change in rhythm made the sentence easier to remember."),
    wordPayload("sustain", "维持；支撑", "Curiosity can sustain a long period of focused learning."),
  ];
  const words = [];
  for (const input of inputs) {
    words.push(await request("/rest/v1/rpc/save_word", { method: "POST", token, body: { p_payload: input } }));
  }

  const plan = await request("/rest/v1/rpc/get_daily_plan", { method: "POST", token, body: {} });
  if (plan.new_suggested < 3 || plan.learned_count < 3) throw new Error("每日计划未统计新收藏单词");

  const targets = await request("/rest/v1/rpc/get_learning_targets", {
    method: "POST", token, body: { p_limit: 10 },
  });
  if (targets.length < 3) throw new Error("学习目标数量异常");

  const reviewed = await request("/rest/v1/rpc/apply_review", {
    method: "POST", token,
    body: { p_word_id: words[0].id, p_quality: 4, p_exercise_type: "self_rating" },
  });
  if (reviewed.repetitions !== 1 || reviewed.status !== "learning") throw new Error("间隔复习状态转换异常");

  const lookup = await request("/functions/v1/lookup-word", {
    method: "POST", token,
    body: { word: "resilient", sentence: inputs[0].sentence, context: inputs[0].context },
  });
  if (!lookup.data?.primaryMeaning) throw new Error(`AI 查词未返回词义: ${JSON.stringify(lookup.data)}`);

  const reading = await request("/functions/v1/generate-reading", {
    method: "POST", token,
    body: { targetWordIds: words.map((word) => word.id), theme: "daily_life", style: "story", difficulty: "intermediate", wordCount: 5 },
  });
  if (!reading.data?.id || reading.data.paragraphs?.length < 3) throw new Error("AI 阅读生成异常");

  await request("/rest/v1/rpc/mark_reading_complete", {
    method: "POST", token,
    body: { p_reading_id: reading.data.id, p_minutes: reading.data.estimated_minutes },
  });

  const activity = await request("/rest/v1/daily_activity?select=*", { token });
  if (activity[0]?.reading_count !== 1 || activity[0]?.reviewed_count !== 1) throw new Error("学习活动汇总异常");

  console.log(JSON.stringify({
    status: "ok",
    checks: [adminBootstrap ? "admin_test_bootstrap" : "signup_requires_confirmation", "email_confirm", "login", "profile_trigger", "save_word", "daily_plan", "learning_targets", "apply_review", "ai_lookup", "ai_reading", "complete_reading", "daily_activity"],
  }, null, 2));
} finally {
  if (userID) {
    await request(`/auth/v1/admin/users/${userID}`, { method: "DELETE", admin: true }).catch((error) => {
      console.error(`测试用户清理失败: ${error.message}`);
      process.exitCode = 1;
    });
  }
}
