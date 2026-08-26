// 模型生命周期巡检：确认生产在用的 OpenRouter 模型还活着、还没被排进下线表。
//
//   本地：node scripts/check-model.mjs        （模型标识从 .env 读）
//   CI  ：由 .github/workflows/keepalive.yml 注入 OPENROUTER_MODEL
//   换模：node scripts/check-model.mjs --live  （多发一次真实请求，见文件末尾）
//
// 为什么需要这个脚本：
//   当前模型 qwen/qwen3.7-flash 在 OpenRouter 上只有阿里云一个供应方，没有路由
//   兜底。而阿里云的下线通知只发给「近三个月调用过该模型的账号」—— 那是
//   OpenRouter 的账号，不是我们的。我们既没有阿里云账号，也拿不到那封邮件，
//   所以模型下线对本项目来说是一次「零预警」事故：三个 Edge Function 同时报错。
//   这两个数据源都是公开页面，不需要任何 API key。
//
// 两条独立的线索，早晚各一条：
//   1. 阿里云下线表 —— 早期预警。主线模型提前 3 个月、快照模型提前 30 天公布；
//   2. OpenRouter 端点 —— 兜底告警。模型真下架时端点会消失，属于「已经出事」。
//
// 不做静默跳过：网络失败、页面改版、表头找不到，一律非零退出。定时任务显示绿色、
// 实际什么都没检查，正是这个脚本要防的那种失败。

import path from "node:path";
import { fileURLToPath } from "node:url";
import { readEnvFile } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ENDPOINTS_API = "https://openrouter.ai/api/v1/models";
// 国际站页面（www.alibabacloud.com）不需要登录；help.aliyun.com 是同一份内容的国内镜像。
const DEPRECATION_PAGE = "https://www.alibabacloud.com/help/en/model-studio/model-depreciation";

function readModelId() {
  const fromEnvironment = process.env.OPENROUTER_MODEL;
  if (fromEnvironment) return fromEnvironment;
  return readEnvFile(path.join(root, ".env")).OPENROUTER_MODEL;
}

const problems = [];
const modelId = readModelId();
if (!modelId) {
  console.error("巡检失败：缺少 OPENROUTER_MODEL（环境变量与 .env 二选一）");
  process.exit(1);
}
// OpenRouter 标识是 "供应商/模型名"，阿里云文档里只用后半段。
const bareName = modelId.includes("/") ? modelId.slice(modelId.indexOf("/") + 1) : modelId;

console.log(`巡检模型：${modelId}\n`);

// ── 线索一：OpenRouter 端点还在不在 ────────────────────────────────────────────

try {
  const response = await fetch(`${ENDPOINTS_API}/${modelId}/endpoints`);
  if (response.status === 404) {
    problems.push(`OpenRouter 已下架 ${modelId}：三个 Edge Function 现在应该全在报错，立即换模型`);
  } else if (!response.ok) {
    problems.push(`OpenRouter 端点接口返回 HTTP ${response.status}，无法确认模型状态`);
  } else {
    const data = (await response.json())?.data;
    const endpoints = Array.isArray(data?.endpoints) ? data.endpoints : [];
    if (!endpoints.length) {
      problems.push(`${modelId} 在 OpenRouter 上已经没有可用端点`);
    }
    for (const endpoint of endpoints) {
      // status 为负表示 OpenRouter 判定该端点异常并已降权或停用。
      const healthy = (endpoint.status ?? 0) >= 0;
      const uptime = endpoint.uptime_last_1d;
      console.log(`  供应方 ${endpoint.provider_name}：status=${endpoint.status ?? 0} 近一天可用率=${typeof uptime === "number" ? `${uptime.toFixed(1)}%` : "未知"}`);
      if (!healthy) problems.push(`端点 ${endpoint.provider_name} 状态异常（status=${endpoint.status}）`);
    }
    // 单供应方本身不是错误，但值得每次打印：它决定了「换模型」是不是唯一的补救手段。
    if (endpoints.length === 1) console.log(`  ⚠️ 只有 ${endpoints[0].provider_name} 一家供应方，无路由兜底\n`);
    else console.log("");
  }
} catch (error) {
  problems.push(`访问 OpenRouter 失败：${error instanceof Error ? error.message : error}`);
}

// ── 线索二：阿里云下线表里有没有它 ────────────────────────────────────────────
//
// 这一页的坑：一个模型名会同时出现在「Model name」列和「Replacement model」列
// —— 后者是说它是别人的接替者，不是它自己要下线（qwen3.6-flash 就是这种情况）。
// 所以不能 grep 整页，必须按列判断。

function stripTags(html) {
  return html
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/\s+/g, " ")
    .trim();
}

// 表格里大量使用 rowspan（同一个下线日期跨十几行），必须还原成网格才能按列取值。
function toGrid(tableHtml) {
  const grid = [];
  const rows = tableHtml.match(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi) ?? [];
  rows.forEach((rowHtml, rowIndex) => {
    grid[rowIndex] ??= [];
    const cells = rowHtml.match(/<t[dh]\b[^>]*>[\s\S]*?<\/t[dh]>/gi) ?? [];
    let column = 0;
    for (const cellHtml of cells) {
      while (grid[rowIndex][column] !== undefined) column += 1; // 跳过被上方 rowspan 占住的格子
      const rowSpan = Number(cellHtml.match(/rowspan="(\d+)"/i)?.[1] ?? 1);
      const colSpan = Number(cellHtml.match(/colspan="(\d+)"/i)?.[1] ?? 1);
      const text = stripTags(cellHtml.replace(/^<t[dh]\b[^>]*>/i, "").replace(/<\/t[dh]>$/i, ""));
      for (let r = 0; r < rowSpan; r += 1) {
        grid[rowIndex + r] ??= [];
        for (let c = 0; c < colSpan; c += 1) grid[rowIndex + r][column + c] = text;
      }
      column += colSpan;
    }
  });
  return grid;
}

try {
  const response = await fetch(DEPRECATION_PAGE, { headers: { "User-Agent": "cijing-model-check" } });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const html = await response.text();

  let tablesUnderstood = 0;
  let listedAs = null;

  for (const tableHtml of html.match(/<table\b[\s\S]*?<\/table>/gi) ?? []) {
    const grid = toGrid(tableHtml);
    const header = grid[0] ?? [];
    const nameColumn = header.findIndex((cell) => /^model name$/i.test(cell ?? ""));
    const timeColumn = header.findIndex((cell) => /^deprecation time$/i.test(cell ?? ""));
    if (nameColumn < 0) continue; // 不是下线表（页面上还有别的表格）
    tablesUnderstood += 1;

    for (const row of grid.slice(1)) {
      if (row?.[nameColumn] !== bareName) continue;
      listedAs = timeColumn >= 0 ? (row[timeColumn] ?? "日期未知") : "日期未知";
    }
  }

  if (!tablesUnderstood) {
    // 页面改版会让「什么都没匹配到」看起来和「安全」一模一样，必须当失败处理。
    problems.push("阿里云下线页解析失败：没找到带「Model name」表头的表格，页面结构可能已变，请人工核对");
  } else if (listedAs) {
    problems.push(`阿里云已把 ${bareName} 排进下线表，下线时间 ${listedAs}，到期后 API 调用直接失败`);
  } else {
    console.log(`  阿里云下线表（已解析 ${tablesUnderstood} 张）里没有 ${bareName}\n`);
  }
} catch (error) {
  problems.push(`访问阿里云下线页失败：${error instanceof Error ? error.message : error}`);
}

// ── 线索三：--live 才跑，用生产同款契约发一次真实请求 ─────────────────────────
//
// 前两条线索只能证明「模型还在」，证明不了「它还接受我们这套请求」。换模型时真正
// 会翻车的是契约：response_format 的 json_schema 严格模式各家支持程度不一，而
// provider.data_collection = "deny" 会把不合规的端点直接过滤掉——过滤到一个不剩
// 时表现为 404，不是「降级到别家」。这两种失败都只有真发一次请求才看得见。
//
// 默认不跑：定时巡检每两天一次，不该为此产生费用和真实调用。

if (process.argv.includes("--live")) {
  const apiKey = process.env.OPENROUTER_API_KEY
    ?? readEnvFile(path.join(root, ".env")).OPENROUTER_API_KEY;
  if (!apiKey) {
    problems.push("--live 需要 OPENROUTER_API_KEY（环境变量与 .env 二选一）");
  } else {
    // 刻意复刻 supabase/functions/_shared/openrouter.ts 的请求形状：改那边时这里要同步。
    const schema = {
      type: "object",
      required: ["word", "meaning"],
      properties: { word: { type: "string" }, meaning: { type: "string" } },
    };
    const started = Date.now();
    try {
      const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://cijing.app",
          "X-Title": "CiJing Vocabulary",
        },
        body: JSON.stringify({
          model: modelId,
          messages: [
            { role: "system", content: `Return only valid JSON matching this exact JSON Schema: ${JSON.stringify(schema)}` },
            { role: "user", content: "Give the Chinese meaning of the English word \"resilient\"." },
          ],
          temperature: 0.35,
          max_tokens: 200,
          reasoning: { enabled: false },
          provider: { data_collection: "deny" },
          response_format: { type: "json_schema", json_schema: { name: "probe", strict: true, schema } },
        }),
      });
      const elapsed = Date.now() - started;
      if (!response.ok) {
        const detail = (await response.text()).slice(0, 300);
        // 404 在这里几乎总是 data_collection 过滤后无端点可用，而不是模型不存在
        // —— 线索一已经证明模型在售了。
        const hint = response.status === 404
          ? "（模型在售却 404：极可能是 data_collection=\"deny\" 过滤后没有合规端点了）"
          : response.status === 400
            ? "（400 常见于上游拒绝 json_schema 严格模式）"
            : "";
        problems.push(`实测请求失败：HTTP ${response.status}${hint} ${detail}`);
      } else {
        const payload = await response.json();
        const content = payload?.choices?.[0]?.message?.content;
        console.log(`  实测请求成功：${elapsed}ms，用量 ${JSON.stringify(payload?.usage ?? {})}`);
        let parsed;
        try {
          parsed = JSON.parse(content);
        } catch {
          problems.push(`实测返回的不是合法 JSON：${String(content).slice(0, 200)}`);
        }
        if (parsed) {
          const missing = schema.required.filter((key) => !(key in parsed));
          if (missing.length) {
            // 不算失败：适配器本来就有本地校验加一次纠正请求兜底。但要说清楚，
            // 因为这意味着严格模式没生效，实际保障来自我们自己的校验。
            console.log(`  ⚠️ 严格 schema 未生效（缺少 ${missing.join("、")}），实际约束依赖本地校验与纠正重试`);
          } else {
            console.log(`  严格 schema 生效：${JSON.stringify(parsed).slice(0, 120)}\n`);
          }
        }
      }
    } catch (error) {
      problems.push(`实测请求异常：${error instanceof Error ? error.message : error}`);
    }
  }
}

// ── 结论 ──────────────────────────────────────────────────────────────────────

if (!problems.length) {
  console.log("巡检通过：模型在售、未列入下线表。");
  process.exit(0);
}

console.error("巡检发现问题：");
for (const problem of problems) console.error(`  ✗ ${problem}`);
console.error(`\n换模步骤见 docs/qwen/qwen3.7-flash.md「验证与换模」：先改 .env 的 OPENROUTER_MODEL，
跑 node scripts/smoke-test.mjs --ai 与 make production-smoke，再 make edge-secrets 推生产。
客户端不需要重新发版。候选模型见 https://openrouter.ai/qwen`);
process.exit(1);
