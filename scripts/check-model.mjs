// 模型生命周期巡检：确认生产在用的 OpenRouter 模型还活着、还没被排进下线表。
//
//   本地：node scripts/check-model.mjs        （模型标识从 .env 读）
//   CI  ：由 .github/workflows/keepalive.yml 注入 OPENROUTER_MODEL
//   换模：node scripts/check-model.mjs --live  （多发一次真实请求，见文件末尾）
//   核对：node scripts/check-model.mjs --accept（人工看过新批次后按下确认，见线索二）
//
// 为什么需要这个脚本：
//   当前模型 qwen/qwen3.7-flash 在 OpenRouter 上只有阿里云一个供应方，没有路由
//   兜底。而阿里云的下线通知只发给「近三个月调用过该模型的账号」—— 那是
//   OpenRouter 的账号，不是我们的。我们既没有阿里云账号，也拿不到那封邮件，
//   所以模型下线对本项目来说是一次「零预警」事故：三个 Edge Function 同时报错。
//   这两个数据源都是公开页面，不需要任何 API key。
//
// 两条独立的线索，早晚各一条：
//   1. OpenRouter 端点 —— 兜底告警。模型真下架时端点会消失，属于「已经出事」；
//   2. 阿里云下线批次 —— 早期预警。主线模型提前 3 个月、快照模型提前 30 天公布。
//
// 不做静默跳过：网络失败、页面改版、批次对不上，一律非零退出。定时任务显示绿色、
// 实际什么都没检查，正是这个脚本要防的那种失败。

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readEnvFile } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ENDPOINTS_API = "https://openrouter.ai/api/v1/models";
// 2026-08-30 换到国内站：国际站（www.alibabacloud.com）的服务端渲染坏了，返回的
// 壳子里 $lang、$productId 这些模板变量都没被替换，正文一个字都没有，换 UA 也一样。
// 国内站是同一份内容，且把正文完整嵌在页面的 __ICE_PAGE_PROPS__ 里，不需要登录。
const DEPRECATION_PAGE = "https://help.aliyun.com/zh/model-studio/model-depreciation";
const BATCH_SNAPSHOT = path.join(root, "scripts", "model-deprecation-batches.json");

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
const today = new Date().toISOString().slice(0, 10);

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
    // 顺手看一眼 OpenRouter 自己的下线日期字段。它极少填（2026-08-30 抽查 396 个模型
    // 只有 7 个有值，Qwen 系列一个都没有，连阿里云已公告 10-10 下线的 qwen3-max 都是空），
    // 所以它只能当白捡的额外信号，绝不能拿来代替线索二。
    if (data?.expiration_date) {
      problems.push(`OpenRouter 给 ${modelId} 标了下线日期 ${data.expiration_date}`);
    }
    // 单供应方本身不是错误，但值得每次打印：它决定了「换模型」是不是唯一的补救手段。
    if (endpoints.length === 1) console.log(`  ⚠️ 只有 ${endpoints[0].provider_name} 一家供应方，无路由兜底\n`);
    else console.log("");
  }
} catch (error) {
  problems.push(`访问 OpenRouter 失败：${error instanceof Error ? error.message : error}`);
}

// ── 线索二：阿里云有没有新的下线批次 ──────────────────────────────────────────
//
// 2026-08-30 重写。原先这一段是「把下线表按列解析，看 Model name 列里有没有我们的
// 模型」，它在 #16 挂了 —— 不是模型出事，是那张表没了：
//
//   下线页现在只剩「下线模型列表」下面一串按日期分组的小标题，每组指向几条
//   www.aliyun.com/notice/<id> 官网公告，具体哪些模型下线写在公告里。而公告页是
//   前端渲染的，清单有的是文字表格、有的干脆是一张图片（118344、118345 都是图），
//   拿不到 HTML 也 OCR 不了。也就是说：「这个模型有没有被点名」这件事，已经没有
//   任何一个公开接口能机器判断了。
//
// 所以这里换一种问法，把「模型在不在表里」换成「有没有新的批次需要人看」：
// 页面上未来日期的批次全部记进 scripts/model-deprecation-batches.json，出现新批次
// 或某个批次追加了公告，就红一次、点名让人去翻公告。批次一年才几次，噪音可以接受，
// 而漏报的代价是三个 Edge Function 同时挂掉。人工核对完跑 --accept 收进快照。

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

// 标题里塞了一堆 <span class="help-letter-space">，剥完标签会变成「2026 年 10 月 10 日」，
// 比对前先把空白全去掉。
const compact = (text) => text.replace(/\s+/g, "");

// 正文以 JSON 字符串的形式挂在 window.__ICE_PAGE_PROPS__ 上，同一行后面还跟着别的
// 语句，不能整段 JSON.parse，只能自己数花括号找对象结尾（字符串里的括号要跳过）。
function extractPageProps(html) {
  const marker = "window.__ICE_PAGE_PROPS__=";
  const start = html.indexOf(marker);
  if (start < 0) return null;
  const body = html.slice(start + marker.length);
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = 0; index < body.length; index += 1) {
    const character = body[index];
    if (inString) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === '"') inString = false;
      continue;
    }
    if (character === '"') inString = true;
    else if (character === "{") depth += 1;
    else if (character === "}") {
      depth -= 1;
      if (depth === 0) {
        try {
          return JSON.parse(body.slice(0, index + 1));
        } catch {
          return null;
        }
      }
    }
  }
  return null;
}

// 「下线模型列表」下面每个 <h3> 是一个批次，正文里的 notice 链接是该批次的公告。
function parseBatches(content) {
  const anchor = content.indexOf('id="下线模型列表"');
  if (anchor < 0) return null;
  const section = content.slice(anchor);
  const batches = [];
  for (const match of section.matchAll(/<h3\b[^>]*>([\s\S]*?)<\/h3>([\s\S]*?)(?=<h[23]\b|$)/g)) {
    const heading = compact(stripTags(match[1]));
    const parts = heading.match(/(\d{4})年(\d{1,2})月(\d{1,2})日/);
    if (!parts) continue;
    const date = `${parts[1]}-${parts[2].padStart(2, "0")}-${parts[3].padStart(2, "0")}`;
    const notices = [...new Set([...match[2].matchAll(/aliyun\.com\/notice\/(\d+)/g)].map((link) => link[1]))].sort();
    // 「将下线」是页面自己的措辞；日期兜一层，防止公告发布后措辞改成别的说法。
    batches.push({ date, heading, notices, pending: heading.includes("将下线") || date >= today });
  }
  return batches;
}

function readSnapshot() {
  if (!fs.existsSync(BATCH_SNAPSHOT)) return { batches: {} };
  try {
    const parsed = JSON.parse(fs.readFileSync(BATCH_SNAPSHOT, "utf8"));
    return { ...parsed, batches: parsed.batches ?? {} };
  } catch (error) {
    problems.push(`读取 ${path.relative(root, BATCH_SNAPSHOT)} 失败：${error instanceof Error ? error.message : error}`);
    return null;
  }
}

let pendingBatches = null;

try {
  const response = await fetch(DEPRECATION_PAGE, { headers: { "User-Agent": "cijing-model-check" } });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const html = await response.text();

  const props = extractPageProps(html);
  const content = props?.docDetailData?.storeData?.data?.content;
  const batches = typeof content === "string" ? parseBatches(content) : null;

  if (!content) {
    // 页面改版会让「什么都没匹配到」看起来和「安全」一模一样，必须当失败处理。
    problems.push("阿里云下线页解析失败：页面里没有 __ICE_PAGE_PROPS__ 正文，渲染方式可能又变了，请人工核对");
  } else if (!batches || !batches.length) {
    problems.push("阿里云下线页解析失败：没找到「下线模型列表」下的批次标题，页面结构可能已变，请人工核对");
  } else {
    pendingBatches = batches.filter((batch) => batch.pending);
    console.log(`  阿里云下线页：解析到 ${batches.length} 个批次，其中 ${pendingBatches.length} 个待下线`);

    // 页面正文本身点名了我们的模型，那就不用等人工翻公告了，直接报。
    const contentText = compact(stripTags(content));
    if (contentText.includes(bareName)) {
      problems.push(`阿里云下线页正文里出现了 ${bareName}，请立刻核对下线时间`);
    }

    const snapshot = readSnapshot();
    if (snapshot) {
      for (const batch of pendingBatches) {
        const known = snapshot.batches[batch.date];
        const links = batch.notices.map((id) => `https://www.aliyun.com/notice/${id}`).join(" ");
        if (!known) {
          problems.push(`阿里云新增待下线批次 ${batch.date}（${batch.heading}）：清单在公告里、可能是图片，脚本判断不了含不含 ${bareName}，请人工核对 ${links}`);
        } else if (known.join(",") !== batch.notices.join(",")) {
          problems.push(`阿里云 ${batch.date} 批次的公告有变动（原 ${known.length} 条、现 ${batch.notices.length} 条）：请人工核对 ${links}`);
        } else {
          console.log(`  ${batch.date} 批次已人工核对过（${batch.notices.length} 条公告），不含 ${bareName}`);
        }
      }
      console.log("");
    }
  }
} catch (error) {
  problems.push(`访问阿里云下线页失败：${error instanceof Error ? error.message : error}`);
}

// --accept：人工翻完公告、确认这些批次不影响我们之后，把当前的待下线批次收进快照。
// 单独做成一个开关而不是自动写文件，是因为「确认过了」这件事只有人能做。
if (process.argv.includes("--accept")) {
  if (!pendingBatches) {
    console.error("--accept 失败：这次没能解析出批次，先把上面的问题解决掉再确认。");
    process.exit(1);
  }
  const batches = {};
  for (const batch of pendingBatches) batches[batch.date] = batch.notices;
  const snapshot = {
    note: "人工核对过的阿里云下线批次。出现新批次或公告有变动时 scripts/check-model.mjs 会报警；翻完公告确认不影响本项目后跑 node scripts/check-model.mjs --accept 更新这里。",
    model: modelId,
    reviewedAt: today,
    batches,
  };
  fs.writeFileSync(BATCH_SNAPSHOT, `${JSON.stringify(snapshot, null, 2)}\n`);
  console.log(`已把 ${pendingBatches.length} 个待下线批次记进 ${path.relative(root, BATCH_SNAPSHOT)}，记得提交。`);
  process.exit(0);
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
  console.log("巡检通过：模型在售，阿里云没有需要核对的新下线批次。");
  process.exit(0);
}

console.error("巡检发现问题：");
for (const problem of problems) console.error(`  ✗ ${problem}`);
console.error(`\n换模步骤见 docs/qwen/qwen3.7-flash.md「验证与换模」：先改 .env 的 OPENROUTER_MODEL，
跑 node scripts/smoke-test.mjs --ai 与 make production-smoke，再 make edge-secrets 推生产。
客户端不需要重新发版。候选模型见 https://openrouter.ai/qwen`);
process.exit(1);
