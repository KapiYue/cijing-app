import { DEFAULT_CONFIG } from "../shared/config.js";
const url = document.getElementById("url"), key = document.getElementById("key"), status = document.getElementById("status");
url.value = DEFAULT_CONFIG.supabaseUrl;
key.value = DEFAULT_CONFIG.supabasePublishableKey;
document.getElementById("test").onclick = async () => {
  status.textContent = "正在测试…";
  const result = await chrome.runtime.sendMessage({ type: "TEST_CONNECTION" });
  status.textContent = result?.ok ? "✓ 连接正常" : `连接失败：${result?.error || "未知错误"}`;
};
