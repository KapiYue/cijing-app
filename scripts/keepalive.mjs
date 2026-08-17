// Supabase 保活：产生一次真实的数据库查询，避免免费版项目因 7 天无活动被暂停。
//
//   本地：node scripts/keepalive.mjs   （配置从 .env 读）
//   CI  ：由 .github/workflows/keepalive.yml 注入环境变量，仓库里没有 .env
//
// 用的是 publishable key。它本来就编译进 iOS App 与 Chrome 扩展、属于公开值，
// 所以不必把 SUPABASE_SECRET_KEY 放进 GitHub Secrets —— 保活这种低价值任务不值得
// 让服务端密钥多一个存放点。

import path from "node:path";
import { fileURLToPath } from "node:url";
import { readEnvFile } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function readConfig() {
  // 环境变量优先：CI 里没有 .env，readEnvFile 会直接抛错。
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
  if (url && key) return { url, key };

  const file = readEnvFile(path.join(root, ".env"));
  return {
    url: url || file.SUPABASE_URL,
    key: key || file.SUPABASE_PUBLISHABLE_KEY || file.SUPABASE_ANON_KEY,
  };
}

const config = readConfig();
const baseURL = config.url?.replace(/\/$/, "");

// 配置缺失时必须报错退出。静默跳过正是「项目被暂停了却没人发现」的成因 ——
// 定时任务显示绿色、实际什么都没做，是最坏的一种失败。
if (!baseURL || !config.key) {
  console.error("保活失败：缺少 SUPABASE_URL 或 SUPABASE_PUBLISHABLE_KEY（环境变量与 .env 二选一）");
  process.exit(1);
}

const started = Date.now();

try {
  const response = await fetch(`${baseURL}/rest/v1/rpc/keepalive`, {
    method: "POST",
    headers: {
      apikey: config.key,
      Authorization: `Bearer ${config.key}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });

  const body = (await response.text()).trim();

  if (!response.ok) {
    // 404 基本等于「202608170005 那份迁移还没应用到这个项目」。
    const hint = response.status === 404 ? "（函数不存在？确认 202608170005_keepalive.sql 已应用）" : "";
    console.error(`保活失败：HTTP ${response.status}${hint} ${body.slice(0, 200)}`);
    process.exit(1);
  }

  console.log(`保活成功：数据库时间 ${body}，耗时 ${Date.now() - started}ms`);
} catch (error) {
  // 项目已被暂停时通常表现为连接层失败，而不是某个 HTTP 状态码。
  console.error(`保活失败：${error instanceof Error ? error.message : error}`);
  process.exit(1);
}
