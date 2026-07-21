import { getConfig } from "./config.js";
import { compatibilityPassword, validateCredentials } from "./auth.js";

const SESSION_KEY = "cijingSession";

function authMessage(payload) {
  return payload.message || payload.error_description || payload.msg || payload.error || "";
}

async function getSession() {
  const value = await chrome.storage.local.get(SESSION_KEY);
  return value[SESSION_KEY] || null;
}

async function setSession(session) {
  if (session) await chrome.storage.local.set({ [SESSION_KEY]: session });
  else await chrome.storage.local.remove(SESSION_KEY);
}

async function refreshSession(session, config) {
  if (!session?.refresh_token) return null;
  const response = await fetch(`${config.supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
    method: "POST",
    headers: { apikey: config.supabasePublishableKey, "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: session.refresh_token })
  });
  if (!response.ok) {
    await setSession(null);
    return null;
  }
  const updated = await response.json();
  await setSession(updated);
  return updated;
}

async function validSession() {
  const config = await getConfig();
  let session = await getSession();
  if (!session) return { config, session: null };
  const expiresAt = Number(session.expires_at || 0) * 1000;
  if (expiresAt < Date.now() + 60_000) session = await refreshSession(session, config);
  return { config, session };
}

async function authenticatedFetch(path, options = {}) {
  const { config, session } = await validSession();
  if (!session?.access_token) throw new Error("AUTH_REQUIRED");
  const response = await fetch(`${config.supabaseUrl}${path}`, {
    cache: "no-store",
    ...options,
    headers: {
      apikey: config.supabasePublishableKey,
      Authorization: `Bearer ${session.access_token}`,
      "Content-Type": "application/json",
      ...(options.headers || {})
    }
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.message || payload.error_description || payload.error || `HTTP_${response.status}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

export async function signUp(email, password) {
  const config = await getConfig();
  const credentials = validateCredentials(email, password, { isSignUp: true });
  const response = await fetch(`${config.supabaseUrl}/auth/v1/signup`, {
    method: "POST",
    headers: { apikey: config.supabasePublishableKey, "Content-Type": "application/json" },
    body: JSON.stringify(credentials)
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = authMessage(payload);
    if (/user already registered|already been registered/i.test(message)) throw new Error("该邮箱已注册，请直接登录。");
    throw new Error(message || "注册失败");
  }
  const hasSession = Boolean(payload.access_token && payload.refresh_token);
  if (hasSession) await setSession(payload);
  return {
    confirmationRequired: !hasSession,
    email: credentials.email,
    session: hasSession ? payload : null
  };
}

export async function signIn(email, password) {
  const config = await getConfig();
  const credentials = validateCredentials(email, password);
  const request = (candidate) => fetch(`${config.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    cache: "no-store",
    credentials: "omit",
    headers: { apikey: config.supabasePublishableKey, "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ email: credentials.email, password: candidate })
  });
  let response = await request(credentials.password);
  let payload = await response.json().catch(() => ({}));
  const cleanedPassword = compatibilityPassword(credentials.password);
  if (!response.ok && /invalid login credentials/i.test(authMessage(payload)) && cleanedPassword !== credentials.password) {
    response = await request(cleanedPassword);
    payload = await response.json().catch(() => ({}));
  }
  if (!response.ok) {
    const message = authMessage(payload);
    if (/email not confirmed/i.test(message)) throw new Error("邮箱尚未验证，请先打开验证邮件完成确认。");
    if (/invalid login credentials/i.test(message)) throw new Error("邮箱或密码不正确。");
    throw new Error(message || "登录失败");
  }
  if (!payload.access_token || !payload.refresh_token) throw new Error("登录成功但服务器未返回完整会话，请重试。");
  await setSession(payload);
  return payload;
}

export async function signOut() {
  const { config, session } = await validSession();
  if (session?.access_token) {
    await fetch(`${config.supabaseUrl}/auth/v1/logout`, {
      method: "POST",
      headers: { apikey: config.supabasePublishableKey, Authorization: `Bearer ${session.access_token}` }
    }).catch(() => {});
  }
  await setSession(null);
}

export async function sessionSummary() {
  const { session } = await validSession();
  return session ? { signedIn: true, email: session.user?.email || "已登录" } : { signedIn: false };
}

export async function lookupWord(payload) {
  return authenticatedFetch("/functions/v1/lookup-word", { method: "POST", body: JSON.stringify(payload) });
}

export async function saveWord(payload) {
  return authenticatedFetch("/rest/v1/rpc/save_word", { method: "POST", body: JSON.stringify({ p_payload: payload }) });
}

export async function getDashboard() {
  const plan = await authenticatedFetch("/rest/v1/rpc/get_daily_plan", { method: "POST", body: "{}" });
  const recent = await authenticatedFetch("/rest/v1/words?select=id,term,primary_meaning,status,created_at&order=created_at.desc&limit=4");
  return { plan, recent };
}

export async function testConnection() {
  const config = await getConfig();
  const response = await fetch(`${config.supabaseUrl}/rest/v1/`, { headers: { apikey: config.supabasePublishableKey } });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return true;
}
