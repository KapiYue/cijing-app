import path from "node:path";
import { fileURLToPath } from "node:url";
import { readEnvFile } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const config = readEnvFile(path.join(root, ".env"));
const baseURL = config.SUPABASE_URL?.replace(/\/$/, "");
const publishableKey = config.SUPABASE_PUBLISHABLE_KEY || config.SUPABASE_ANON_KEY;
const secretKey = config.SUPABASE_SECRET_KEY;
if (!baseURL || !publishableKey || !secretKey) throw new Error("账号删除验收缺少 Supabase 环境变量");

const runID = Date.now();
const email = `cijing_delete_e2e_${runID}@cijing.joy-coder.com`;
const password = `CiJing-Delete-${runID}!`;
let userID;

async function fetchJSON(apiPath, { method = "GET", body, token, admin = false } = {}) {
  const apiKey = admin ? secretKey : publishableKey;
  const response = await fetch(`${baseURL}${apiPath}`, {
    method,
    headers: {
      apikey: apiKey,
      Authorization: `Bearer ${token || apiKey}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  return { response, payload };
}

try {
  const signup = await fetchJSON("/auth/v1/signup", { method: "POST", body: { email, password } });
  if (!signup.response.ok) throw new Error(`注册临时账号失败：HTTP ${signup.response.status}`);
  userID = signup.payload.user?.id;
  const token = signup.payload.access_token;
  if (!userID || !token) throw new Error("临时账号没有返回可用会话");

  const deletion = await fetchJSON("/functions/v1/delete-account", { method: "POST", token, body: {} });
  if (!deletion.response.ok || deletion.payload.deleted !== true) {
    throw new Error(`自助删除失败：HTTP ${deletion.response.status} ${JSON.stringify(deletion.payload).slice(0, 300)}`);
  }

  const loginAfterDeletion = await fetchJSON("/auth/v1/token?grant_type=password", {
    method: "POST",
    body: { email, password },
  });
  if (loginAfterDeletion.response.ok) throw new Error("账号删除后仍然可以登录");

  const adminLookup = await fetchJSON(`/auth/v1/admin/users/${userID}`, { admin: true });
  if (adminLookup.response.ok) throw new Error("账号删除后 Auth 用户仍然存在");

  console.log(JSON.stringify({
    status: "ok",
    checks: ["authenticated_self_delete", "login_rejected_after_delete", "auth_user_removed"],
  }, null, 2));
  userID = undefined;
} finally {
  if (userID) {
    await fetchJSON(`/auth/v1/admin/users/${userID}`, { method: "DELETE", admin: true }).catch(() => {});
  }
}
