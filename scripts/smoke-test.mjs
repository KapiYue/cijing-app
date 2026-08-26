import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnv } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
loadEnv(path.join(root, ".env"));

const baseURL = process.env.SUPABASE_URL;
const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
// 邮箱确认打开后（config.toml 的 enable_confirmations，f1f8dbb 起）注册不再直接返回
// 会话，必须先用管理员接口确认邮箱再密码登录，本机栈同样如此。本地的 secret key
// 由 ./scripts/supabase.sh status 打印。
const secretKey = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!baseURL || !publishableKey) throw new Error(".env 中缺少 SUPABASE_URL 或 SUPABASE_PUBLISHABLE_KEY");
if (!secretKey) throw new Error(".env 中缺少 SUPABASE_SECRET_KEY：注册需要邮箱确认，冒烟测试要用管理员接口自助确认");

// 这个脚本会真的注册用户、存词、写学习活动。对着本机栈无所谓（db reset 一把冲掉），
// 对着生产就是往真实用户表里插测试数据 —— 而 .env 的 SUPABASE_URL 指向哪里，跑的人
// 多半不会每次都确认一遍。所以默认只允许本机地址，指向别处必须自己说出来。
// 生产验收有专门的脚本：make production-smoke（scripts/production-smoke-test.mjs）。
const isLocal = /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])(:|\/|$)/.test(baseURL);
if (!isLocal && !process.argv.includes("--allow-remote")) {
  throw new Error(`SUPABASE_URL 指向的不是本机（${baseURL}）。生产验收请用 make production-smoke；确实要对着远端跑本脚本，加 --allow-remote。`);
}
const email = `smoke_${Date.now()}@cijing.joy-coder.com`;
const password = "CiJing-local-123!";

async function request(path, { body, token, admin = false, method } = {}) {
  const apiKey = admin ? secretKey : publishableKey;
  const response = await fetch(`${baseURL}${path}`, {
    method: method ?? (body ? "POST" : "GET"),
    headers: { apikey: apiKey, "Content-Type": "application/json", ...(token || admin ? { Authorization: `Bearer ${token || apiKey}` } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status} ${JSON.stringify(payload).slice(0, 500)}`);
  return payload;
}

const signup = await request("/auth/v1/signup", { body: { email, password } });
if (signup.access_token) throw new Error("注册直接返回了会话：邮箱确认被关掉了，本机行为已与生产不一致");
let userID = signup.user?.id;
if (!userID) {
  const users = await request("/auth/v1/admin/users?page=1&per_page=1000", { admin: true });
  userID = users.users?.find((user) => user.email?.toLowerCase() === email.toLowerCase())?.id;
}
if (!userID) throw new Error("注册未返回会话，管理员也查不到待确认用户");
await request(`/auth/v1/admin/users/${userID}`, { method: "PUT", admin: true, body: { email_confirm: true } });

const session = await request("/auth/v1/token?grant_type=password", { body: { email, password } });
const token = session.access_token;
if (!token) throw new Error("确认邮箱后密码登录仍未返回会话");

// 从这里开始必须保证清理：本脚本原本只跑本机栈（脏数据 db reset 一把冲掉），
// 但 .env 的 SUPABASE_URL 完全可能指向生产。没有 finally 的话，每跑一次就在生产
// 库里永久留下一个测试用户、一条词和一天的学习活动，而且不会有任何人发现。
// 与 production-smoke-test.mjs 保持同一套清理约定。
try {
  const word = await request("/rest/v1/rpc/save_word", { token, body: { p_payload: {
    term: "resilient", lemma: "resilient", phonetic: "rɪˈzɪliənt",
    parts: [{ partOfSpeech: "adj.", meaning: "有韧性的；能迅速恢复的" }],
    primary_meaning: "有韧性的；能迅速恢复的", contextual_meaning: "遇到困难后仍能恢复",
    example_en: "The resilient team adapted quickly.", example_zh: "这支有韧性的团队很快适应了。",
    context: "The resilient team adapted quickly when the plan changed.", sentence: "The resilient team adapted quickly.",
    source_title: "词鲸背单词 smoke test"
  } } });

  const plan = await request("/rest/v1/rpc/get_daily_plan", { token, body: {} });
  if (!word.id || plan.new_suggested < 1) throw new Error("Word save or daily plan assertion failed");

  if (process.argv.includes("--ai")) {
    const lookup = await request("/functions/v1/lookup-word", { token, body: { word: "resilient", sentence: "The resilient team adapted quickly.", context: "The resilient team adapted quickly when the plan changed." } });
    if (!lookup.data?.primaryMeaning) throw new Error("AI lookup assertion failed");
  }

  console.log(`词鲸背单词 smoke test OK: auth → save_word → daily_plan${process.argv.includes("--ai") ? " → OpenRouter lookup" : ""}`);
} finally {
  // 删除用户会连带清掉它名下受 RLS 保护的词库与活动数据。
  await request(`/auth/v1/admin/users/${userID}`, { method: "DELETE", admin: true }).catch((error) => {
    console.error(`测试用户清理失败（${email}）：${error.message}`);
    process.exitCode = 1;
  });
}
