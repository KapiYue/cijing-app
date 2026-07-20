import path from "node:path";
import { fileURLToPath } from "node:url";
import { readEnvFile } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const config = readEnvFile(path.join(root, ".env"));
const baseURL = config.SUPABASE_URL?.replace(/\/$/, "");
const publishableKey = config.SUPABASE_PUBLISHABLE_KEY || config.SUPABASE_ANON_KEY;
const secretKey = config.SUPABASE_SECRET_KEY;

if (!baseURL || !publishableKey || !secretKey) {
  throw new Error(".env 中缺少 SUPABASE_URL、SUPABASE_PUBLISHABLE_KEY 或 SUPABASE_SECRET_KEY");
}

async function getJSON(url, key) {
  const response = await fetch(url, { headers: { apikey: key, Authorization: `Bearer ${key}` } });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`${new URL(url).pathname}: HTTP ${response.status}`);
  return payload;
}

const requiredTables = [
  "profiles", "words", "word_contexts", "review_events", "reading_sessions",
  "practice_attempts", "voice_attempts", "daily_activity", "lexicon_cache",
];
const requiredRPCs = ["save_word", "apply_review", "get_daily_plan", "get_learning_targets", "mark_reading_complete"];
const requiredFunctions = ["lookup-word", "generate-reading", "explain-reading-word"];

const residueQuery = new URLSearchParams({
  select: "id",
  first_source_title: "like.词鲸背单词 E2E *",
});
const [openapi, authSettings, adminUsers, testWords] = await Promise.all([
  getJSON(`${baseURL}/rest/v1/`, secretKey),
  getJSON(`${baseURL}/auth/v1/settings`, publishableKey),
  getJSON(`${baseURL}/auth/v1/admin/users?page=1&per_page=1000`, secretKey),
  getJSON(`${baseURL}/rest/v1/words?${residueQuery}`, secretKey),
]);

const definitions = new Set(Object.keys(openapi.definitions ?? {}));
const paths = new Set(Object.keys(openapi.paths ?? {}));
const functionStatus = {};
for (const name of requiredFunctions) {
  const response = await fetch(`${baseURL}/functions/v1/${name}`, {
    method: "POST",
    headers: { apikey: publishableKey, "Content-Type": "application/json" },
    body: "{}",
  });
  functionStatus[name] = response.status === 404 ? "missing" : "deployed";
}

const report = {
  projectRef: new URL(baseURL).hostname.split(".")[0],
  tables: Object.fromEntries(requiredTables.map((name) => [name, definitions.has(name) ? "present" : "missing"])),
  rpcs: Object.fromEntries(requiredRPCs.map((name) => [name, paths.has(`/rpc/${name}`) ? "present" : "missing"])),
  edgeFunctions: functionStatus,
  auth: {
    emailEnabled: authSettings.external?.email ?? authSettings.disable_signup === false,
    signupDisabled: authSettings.disable_signup ?? null,
    emailConfirmationRequired: authSettings.mailer_autoconfirm === false,
  },
  testResidue: {
    users: (adminUsers.users ?? []).filter((user) => user.email?.startsWith("cijing-e2e-")).length,
    words: testWords.length,
  },
};

console.log(JSON.stringify(report, null, 2));
if (Object.values(report.tables).includes("missing") || Object.values(report.rpcs).includes("missing")) process.exitCode = 2;
if (Object.values(report.edgeFunctions).includes("missing")) process.exitCode = 3;
if (report.testResidue.users > 0 || report.testResidue.words > 0) process.exitCode = 4;
