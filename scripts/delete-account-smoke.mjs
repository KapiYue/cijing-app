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
  if (!userID) {
    const users = await fetchJSON("/auth/v1/admin/users?page=1&per_page=1000", { admin: true });
    userID = users.payload.users?.find((user) => user.email?.toLowerCase() === email.toLowerCase())?.id;
  }
  if (!userID) throw new Error("注册请求未返回用户，管理员也未查询到待确认账号");

  // 生产要求邮箱验证，注册不会直接返回会话。与 production-smoke-test.mjs 一致，
  // 先用管理员接口确认邮箱，再走正常密码登录拿到用户自己的令牌。
  let token = signup.payload.access_token;
  if (!token) {
    await fetchJSON(`/auth/v1/admin/users/${userID}`, {
      method: "PUT", admin: true, body: { email_confirm: true },
    });
    const session = await fetchJSON("/auth/v1/token?grant_type=password", {
      method: "POST", body: { email, password },
    });
    if (!session.response.ok) throw new Error(`确认邮箱后登录失败：HTTP ${session.response.status}`);
    token = session.payload.access_token;
  }
  if (!token) throw new Error("临时账号没有返回可用会话");

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
