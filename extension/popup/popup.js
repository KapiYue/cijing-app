import { normalizeEmail, validateCredentials } from "../shared/auth.js";
import { getPreferences, isHostDisabled, THEME_OPTIONS, updatePreferences } from "../shared/preferences.js";

const $ = (id) => document.getElementById(id);
const send = (message) => chrome.runtime.sendMessage(message);
const PRIVACY_POLICY_URL = "https://cijing.joy-coder.com/privacy";
let activeHost = "";
let preferences;

async function init() {
  $("settings").onclick = () => {
    if (!$("dashboard").hidden) $("preferences").scrollIntoView({ behavior: "smooth", block: "start" });
    else chrome.runtime.openOptionsPage();
  };
  configurePrivacyPolicyLink();
  $("data-consent").onchange = () => updateAuthButtons();
  $("signin").onclick = () => authenticate("SIGN_IN");
  $("signup").onclick = () => authenticate("SIGN_UP");
  $("signout").onclick = async () => { await send({ type: "SIGN_OUT" }); showAuth(); };
  $("more-settings").onclick = () => chrome.runtime.openOptionsPage();
  bindPreferenceControls();
  updateAuthButtons();

  [preferences, activeHost] = await Promise.all([getPreferences(), getActiveHost()]);
  renderPreferences(preferences);

  const response = await send({ type: "GET_SESSION" });
  if (response?.ok && response.data.signedIn) await showDashboard(response.data.email);
  else showAuth();
}

function showAuth() {
  $("loading").hidden = true;
  $("dashboard").hidden = true;
  $("auth").hidden = false;
}

async function authenticate(type) {
  const email = normalizeEmail($("email").value);
  const password = $("password").value;
  $("email").value = email;
  $("auth-error").hidden = true;
  $("auth-notice").hidden = true;
  if (!$("data-consent").checked) {
    $("auth-error").textContent = "请先确认数据使用说明。";
    $("auth-error").hidden = false;
    return;
  }
  try { validateCredentials(email, password, { isSignUp: type === "SIGN_UP" }); }
  catch (error) { $("auth-error").textContent = error.message; $("auth-error").hidden = false; return; }

  setAuthBusy(true);
  const response = await send({ type, email, password }).catch(() => null);
  setAuthBusy(false);
  if (!response?.ok) { $("auth-error").textContent = response?.error || "操作失败"; $("auth-error").hidden = false; return; }
  if (type === "SIGN_UP" && response.data.confirmationRequired) {
    $("password").value = "";
    $("auth-notice").textContent = "注册成功，请打开验证邮件完成确认后再登录。";
    $("auth-notice").hidden = false;
    return;
  }
  await showDashboard(email);
}

async function showDashboard(email) {
  $("loading").hidden = true;
  $("auth").hidden = true;
  $("dashboard").hidden = false;
  $("account-label").textContent = email;
  const response = await send({ type: "GET_DASHBOARD" });
  if (!response?.ok) {
    $("recent").innerHTML = '<div class="empty">同步暂时不可用，请稍后重试。</div>';
    return;
  }
  const plan = response.data.plan || {};
  $("review-count").textContent = plan.review_due ?? 0;
  $("new-count").textContent = plan.new_suggested ?? 0;
  $("weak-count").textContent = plan.weak_count ?? 0;
  const recent = response.data.recent || [];
  $("recent").innerHTML = recent.length
    ? recent.map((word) => `<div class="word-row"><strong>${escapeHTML(word.term)}</strong><span>${escapeHTML(word.primary_meaning)}</span></div>`).join("")
    : '<div class="empty">还没有收藏词，去读一篇英文文章吧。</div>';
}

function bindPreferenceControls() {
  const bindings = [
    ["auto-save", "autoSave"],
    ["save-context", "saveContext"],
    ["privacy-mode", "privacyMode"]
  ];
  for (const [id, key] of bindings) {
    $(id).addEventListener("change", async (event) => {
      preferences = await updatePreferences({ [key]: event.currentTarget.checked });
      renderPreferences(preferences);
    });
  }
  $("site-toggle").onclick = async () => {
    if (!activeHost) return;
    const siteButton = $("site-toggle");
    const siteStatus = $("site-status");
    const wasDisabled = isHostDisabled(preferences, activeHost);
    siteButton.disabled = true;
    siteStatus.hidden = true;
    const hosts = new Set(preferences.disabledHosts);
    if (hosts.has(activeHost)) hosts.delete(activeHost); else hosts.add(activeHost);
    try {
      preferences = await updatePreferences({ disabledHosts: [...hosts] });
      renderPreferences(preferences);
      siteStatus.textContent = wasDisabled
        ? `✓ 已在 ${activeHost} 重新启用查词`
        : `✓ 已在 ${activeHost} 停用查词`;
      siteStatus.dataset.state = "success";
      siteStatus.hidden = false;
    } catch {
      renderPreferences(preferences);
      siteStatus.textContent = "设置没有保存成功，请重试。";
      siteStatus.dataset.state = "error";
      siteStatus.hidden = false;
    }
  };
}

function renderPreferences(value) {
  preferences = value;
  document.body.dataset.theme = value.theme;
  $("auto-save").checked = value.autoSave;
  $("save-context").checked = value.saveContext && !value.privacyMode;
  $("privacy-mode").checked = value.privacyMode;
  $("save-context").disabled = value.privacyMode;
  $("save-context-copy").textContent = value.privacyMode ? "隐私模式开启时暂停" : "收藏当前句子和页面来源";

  const siteButton = $("site-toggle");
  siteButton.disabled = !activeHost;
  const disabled = isHostDisabled(value, activeHost);
  siteButton.setAttribute("aria-pressed", String(disabled));
  siteButton.classList.toggle("active", !disabled && Boolean(activeHost));
  siteButton.textContent = !activeHost
    ? "当前页面不可设置"
    : disabled ? `在 ${activeHost} 启用查词` : `在 ${activeHost} 禁用查词`;

  $("theme-options").innerHTML = THEME_OPTIONS.map((theme) =>
    `<button class="theme-dot${theme.id === value.theme ? " selected" : ""}" data-theme="${theme.id}" style="--swatch:${theme.color}" title="${theme.label}" aria-label="${theme.label}"></button>`
  ).join("");
  $("theme-options").querySelectorAll("[data-theme]").forEach((button) => {
    button.onclick = async () => {
      preferences = await updatePreferences({ theme: button.dataset.theme });
      renderPreferences(preferences);
    };
  });
}

function configurePrivacyPolicyLink() {
  const link = $("privacy-policy-link");
  if (!PRIVACY_POLICY_URL) return;
  link.href = PRIVACY_POLICY_URL;
  link.target = "_blank";
  link.rel = "noreferrer";
  link.textContent = "查看完整隐私政策";
  link.removeAttribute("aria-disabled");
}

function updateAuthButtons(busy = false) {
  const disabled = busy || !$("data-consent").checked;
  $("signin").disabled = disabled;
  $("signup").disabled = disabled;
}

function setAuthBusy(busy) {
  updateAuthButtons(busy);
  $("email").disabled = busy;
  $("password").disabled = busy;
}

async function getActiveHost() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  try {
    const url = new URL(tab?.url || "");
    return ["http:", "https:"].includes(url.protocol) ? url.hostname.toLowerCase() : "";
  } catch { return ""; }
}

function escapeHTML(value = "") {
  return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

init();
