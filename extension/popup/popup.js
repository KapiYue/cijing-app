const $ = (id) => document.getElementById(id);
const send = (message) => chrome.runtime.sendMessage(message);

async function init() {
  $("settings").onclick = () => chrome.runtime.openOptionsPage();
  $("signin").onclick = () => authenticate("SIGN_IN");
  $("signup").onclick = () => authenticate("SIGN_UP");
  $("signout").onclick = async () => { await send({ type: "SIGN_OUT" }); showAuth(); };
  const response = await send({ type: "GET_SESSION" });
  if (response?.ok && response.data.signedIn) await showDashboard(response.data.email);
  else showAuth();
}

function showAuth() {
  $("loading").hidden = true; $("dashboard").hidden = true; $("auth").hidden = false;
}

async function authenticate(type) {
  const email = $("email").value.trim(); const password = $("password").value;
  $("auth-error").hidden = true;
  if (!email || password.length < 6) { $("auth-error").textContent = "请输入有效邮箱和至少 6 位密码。"; $("auth-error").hidden = false; return; }
  const button = type === "SIGN_IN" ? $("signin") : $("signup"); button.disabled = true;
  const response = await send({ type, email, password }); button.disabled = false;
  if (!response?.ok) { $("auth-error").textContent = response?.error || "操作失败"; $("auth-error").hidden = false; return; }
  if (!response.data.access_token) { $("auth-error").textContent = "请检查邮箱完成确认后再登录。"; $("auth-error").hidden = false; return; }
  await showDashboard(email);
}

async function showDashboard(email) {
  $("loading").hidden = true; $("auth").hidden = true; $("dashboard").hidden = false; $("account").textContent = email;
  const response = await send({ type: "GET_DASHBOARD" });
  if (!response?.ok) return;
  const plan = response.data.plan || {};
  $("review-count").textContent = plan.review_due ?? 0; $("new-count").textContent = plan.new_suggested ?? 0; $("weak-count").textContent = plan.weak_count ?? 0;
  const recent = response.data.recent || [];
  $("recent").innerHTML = recent.length ? recent.map((word) => `<div class="word-row"><strong>${escapeHTML(word.term)}</strong><span>${escapeHTML(word.primary_meaning)}</span></div>`).join("") : '<div class="empty">还没有收藏词，去读一篇英文文章吧。</div>';
}

function escapeHTML(value = "") { return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]); }
init();

