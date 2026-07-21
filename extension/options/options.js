import { DEFAULT_PREFERENCES, getPreferences, THEME_OPTIONS, updatePreferences } from "../shared/preferences.js";

const $ = (id) => document.getElementById(id);
let preferences;

async function init() {
  const [loaded, session] = await Promise.all([
    getPreferences(),
    chrome.runtime.sendMessage({ type: "GET_SESSION" })
  ]);
  preferences = loaded;
  $("account").textContent = session?.ok && session.data.signedIn ? session.data.email : "尚未登录";
  bindControls();
  render();
}

function bindControls() {
  for (const [id, key] of [["auto-save", "autoSave"], ["save-context", "saveContext"], ["privacy-mode", "privacyMode"]]) {
    $(id).onchange = async (event) => {
      preferences = await updatePreferences({ [key]: event.currentTarget.checked });
      render();
    };
  }
  $("test").onclick = async () => {
    const status = $("status");
    status.hidden = false;
    status.textContent = "正在检查同步服务…";
    const result = await chrome.runtime.sendMessage({ type: "TEST_CONNECTION" });
    status.textContent = result?.ok ? "✓ 同步服务连接正常" : "同步暂时不可用，请稍后重试。";
  };
  $("reset").onclick = async () => {
    preferences = await updatePreferences(DEFAULT_PREFERENCES);
    render();
  };
}

function render() {
  document.body.dataset.theme = preferences.theme;
  $("auto-save").checked = preferences.autoSave;
  $("save-context").checked = preferences.saveContext;
  $("save-context").disabled = preferences.privacyMode;
  $("privacy-mode").checked = preferences.privacyMode;

  $("themes").innerHTML = THEME_OPTIONS.map((theme) =>
    `<button class="theme${theme.id === preferences.theme ? " selected" : ""}" data-theme="${theme.id}" style="--swatch:${theme.color}"><i></i>${theme.label}</button>`
  ).join("");
  $("themes").querySelectorAll("[data-theme]").forEach((button) => {
    button.onclick = async () => {
      preferences = await updatePreferences({ theme: button.dataset.theme });
      render();
    };
  });

  $("disabled-sites").innerHTML = preferences.disabledHosts.length
    ? preferences.disabledHosts.map((host) => `<div class="disabled-site"><strong>${escapeHTML(host)}</strong><button data-host="${escapeHTML(host)}">重新启用</button></div>`).join("")
    : '<div class="empty">所有网站都可以使用双击查词。</div>';
  $("disabled-sites").querySelectorAll("[data-host]").forEach((button) => {
    button.onclick = async () => {
      preferences = await updatePreferences({ disabledHosts: preferences.disabledHosts.filter((host) => host !== button.dataset.host) });
      render();
    };
  });
}

function escapeHTML(value = "") {
  return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

init();
