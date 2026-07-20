import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnv } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
loadEnv(path.join(root, ".env"));

const baseURL = process.env.SUPABASE_URL;
const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
if (!baseURL || !publishableKey) throw new Error(".env 中缺少 SUPABASE_URL 或 SUPABASE_PUBLISHABLE_KEY");
const email = `smoke-${Date.now()}@cijing.local`;
const password = "CiJing-local-123!";

async function request(path, { body, token } = {}) {
  const response = await fetch(`${baseURL}${path}`, {
    method: body ? "POST" : "GET",
    headers: { apikey: publishableKey, "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status} ${JSON.stringify(payload).slice(0, 500)}`);
  return payload;
}

const session = await request("/auth/v1/signup", { body: { email, password } });
if (!session.access_token) throw new Error("Signup did not return a development session");
const token = session.access_token;

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
