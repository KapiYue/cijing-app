# Qwen3.7 Flash 集成说明

更新日期：2026 年 8 月 26 日

词鲸当前通过 OpenRouter 使用模型标识 `qwen/qwen3.7-flash`，用于词义中文补充、阅读内查词和个性化双语短文生成。模型不直接暴露给 iOS 或 Chrome 扩展；所有调用都发生在已认证的 Supabase Edge Functions 中。

OpenRouter 当前将该模型描述为 Qwen 3.7 系列的快速模型（2026-07-27 发布），并列出文本、图像、视频输入和 1M 上下文、最大输出 65536 token。词鲸只使用文本聊天补全和结构化 JSON 输出，不依赖多模态或超长上下文；供应商能力、路由、价格和可用性可能变化，发布前应以 [OpenRouter 模型页](https://openrouter.ai/qwen/qwen3.7-flash) 为准。

价格按输入长度分档，本项目全部请求都落在最便宜的一档（输入远小于 32k）：输入 $0.03、输出 $0.13 每百万 token。

## 配置

根目录 `.env`：

```dotenv
OPENROUTER_API_KEY=your_key_here
OPENROUTER_MODEL=qwen/qwen3.7-flash
```

本地启动：

```bash
make functions
```

推送托管 secrets：

```bash
make edge-secrets
```

两个命令都通过 `scripts/edge-env.mjs` 从根 `.env` 读取配置，生成权限为 `0600` 的临时环境文件，调用仓库固定版本的 Supabase CLI 后删除临时文件。不要把 API key 写进 `supabase/config.toml`、客户端配置、迁移或本文档。

`supabase/functions/_shared/openrouter.ts` 会拒绝 `openai/`、`anthropic/` 和 `google/` 前缀。替换模型时必须使用项目允许的供应商，并重新验证结构化输出和中文质量。

## 从 Qwen3.6 Flash 换代的记录（2026-08-26）

换代动机是成本：3.6-flash 是 $0.1875 / $1.125 每百万 token，3.7-flash 在本项目所处的档位是 $0.03 / $0.13，输出侧便宜约 8.6 倍，按一篇阅读输入 800、输出 3000 token 估算，单篇成本从约 ¥0.023 降到约 ¥0.0026。

同时评估过「绕开 OpenRouter 直连阿里云百炼」，**没有采纳**：百炼华北 2（北京）的 3.7-flash 是 ¥0.2 / ¥0.8 每百万 token，与经 OpenRouter 的价格基本持平，省下的那点差价换不回重写适配器、改区域绑定的 API Key、跨境调用延迟、内容安全过滤这些新增风险，也会失去「改一个环境变量就换模型」的回退能力。该方案的真正价值在数据不出境与原生 JSON Schema，属于独立的合规/架构决策，不与本次换代混做。

**结构化输出曾有一处文档打架，已用实测判定**：OpenRouter 的端点元数据里 3.7-flash 的 `supported_parameters` **不含** `structured_outputs`（只有 `response_format`），而阿里云百炼文档说 JSON Schema 严格模式只支持 Qwen3.7 及以上系列。2026-08-26 用生产同款契约实测（`node scripts/check-model.mjs --live`）：**严格 schema 实际生效**，`data_collection = "deny"` 过滤后仍有可用端点，`reasoning.enabled = false` 生效（`reasoning_tokens` 为 0），89 token 的探针请求耗时 1.3s、花费 $0.0000048。结论是 OpenRouter 的元数据滞后，适配器无需改动。

每次换模都要重跑这条实测。它是唯一能同时验证「json_schema 严格模式」与「data_collection 过滤后还有端点」的手段——后者失败时表现为 404，看起来像模型不存在，但线索一会同时显示模型在售，两者一对照就能分辨。

供应方没有变化：3.6-flash 与 3.7-flash 在 OpenRouter 上都由 `Alibaba` 单一供应方提供（总部 SG，数据中心 SG 与 CN），条款、隐私政策与数据中心分布不因这次换代而改变。

## 请求契约

共享适配器调用 `POST https://openrouter.ai/api/v1/chat/completions`，设置：

- `reasoning.enabled = false`：学习功能优先低延迟，不消费或展示推理过程；
- `response_format.type = json_schema` 与 `strict = true`：要求精确结构；
- 默认 `temperature = 0.35`、`max_tokens = 2200`；
- 阅读生成使用 `temperature = 0.55`、`max_tokens = 5200`，重新生成时温度为 `0.72`；
- `provider.data_collection = "deny"`：只允许路由到声明不收集输入用于训练的端点；当前模型不在 OpenRouter 公布的 ZDR 列表中，不能宣称零保留；
- `HTTP-Referer` 与 `X-Title` 只用于 OpenRouter 请求来源标识。

返回内容会再次由本地 `schemaIssues` 校验。第一次响应缺字段或类型错误时，适配器最多发起一次带错误摘要的纠正请求；第二次仍不合规则返回 `OPENROUTER_SCHEMA_MISMATCH`，不会把未校验文本写入业务表。

## 三类任务

### `lookup-word`

服务端输入上限为英文单词 61 个字符、句子 600 字符和上下文 1800 字符；当前 Chrome 扩展只发送包含选词且最多 600 字符的当前句子，不发送所在段落。Free Dictionary API 提供带来源和许可元数据的英文释义、音标与音频候选，Qwen 补充中文释义、语境义和例句。结果按用户、词形、上下文哈希缓存 90 天。

### `explain-reading-word`

输入为阅读中的目标单词和最多 800 字符的句子。输出词形、音标、词性、中文释义和当前句中的语境义；同样优先采用公开词典事实并写入用户级缓存。

### `generate-reading`

从当前用户词库选择 3–15 个目标词，输入词形、语境义、难度、主题和文体。输出标题、副标题及 3–7 个英中对应段落。提示词要求每个目标词自然出现，不允许 Markdown、词表、练习或括注。

## 数据最小化

- 不向 OpenRouter 发送邮箱、密码、访问令牌、用户 ID、页面 Cookie 或完整浏览历史；
- 查词仅发送用户主动选择的词及包含该词、最多 600 字符的当前句子；扩展隐私模式会在请求前清空句子和页面来源；
- 阅读生成只发送选中的目标词及释义、主题、文体和难度；
- 模型输出写入当前用户受 RLS 保护的缓存或阅读记录；
- 上游服务对请求的保留与处理仍受其条款和隐私政策约束，产品政策变化时必须同步复核 [`docs/privacy-policy.md`](../privacy-policy.md) 与 [`docs/third-party-content-and-ai-compliance.md`](../third-party-content-and-ai-compliance.md)。

## 验证与换模

只验证模型契约本身，不需要 Supabase：

```bash
node scripts/check-model.mjs --live
```

只验证本地非 AI 路径：

```bash
make smoke
```

产生一次真实模型请求：

```bash
node scripts/smoke-test.mjs --ai
```

换模或供应商路由变化时至少验证：

1. 三种 JSON Schema 都能稳定返回必需字段和类型；
2. 音标、词性、中文语境义及中英段落对应准确；
3. 阅读确实自然包含所有目标词，没有 Markdown 或额外说明；
4. 延迟、错误率、重试次数和成本符合发布预算；
5. 模型条款、数据使用方式和地区可用性与隐私政策一致；
6. `make production-smoke` 通过后再切换生产 `OPENROUTER_MODEL`。

回退时只需把托管环境的 `OPENROUTER_MODEL` 恢复为上一个已验证标识并重新推送 secret，无需重新发布客户端。若响应契约本身发生变化，应先更新共享适配器、测试和文档，再部署 Edge Functions。

## 生命周期监控

阿里云的下线通知只发给近三个月调用过该模型的账号，那是 OpenRouter 的账号，不是本项目的；项目也没有阿里云账号。所以模型下线对我们是零预警事故，必须主动巡检：

```bash
make model-check
```

`scripts/check-model.mjs` 查两个公开数据源，都不需要 API key：OpenRouter 端点接口确认模型还在售、端点是否健康；[阿里云模型下线页](https://help.aliyun.com/zh/model-studio/model-depreciation) 确认没有需要人工核对的新下线批次。

2026-08-30 重写了第二条线索，起因是 keepalive #16 报「没找到带 Model name 表头的表格」——不是模型出事，是那张表没了。下线页现在只剩「下线模型列表」下面一串按日期分组的批次标题，各自指向几条 `www.aliyun.com/notice/<id>` 官网公告，具体哪些模型下线写在公告里；而公告页是前端渲染的，清单有的是文字表格、有的干脆是一张图片（118344、118345 都是图）。也就是说「这个模型有没有被点名」已经没有任何公开接口能机器判断，所以脚本改成盯「有没有新批次要看」：未来日期的批次记在 `scripts/model-deprecation-batches.json`，出现新批次或某批次追加了公告就报警，人工翻完公告、确认不影响本项目后跑 `node scripts/check-model.mjs --accept` 收进快照并提交。批次一年才几次，噪音可以接受，漏报的代价是三个 Edge Function 同时挂掉。

数据源同时从国际站换到国内站：`www.alibabacloud.com` 的服务端渲染已经坏了，返回的壳子里 `$lang`、`$productId` 这些模板变量都没被替换，正文一个字都没有，换 UA 也一样；国内站是同一份内容，且把正文完整嵌在页面的 `__ICE_PAGE_PROPS__` 里，同样不需要登录。

同一份检查挂在 `.github/workflows/keepalive.yml` 的最后一步，两天跑一次；巡检失败会让该次运行标红。放最后是因为前面两步关系到后端保活，不能被一次模型告警顺带停掉。换模型时要同步更新仓库变量 `OPENROUTER_MODEL`，否则巡检的是线上早就不用的标识。

主线模型提前 3 个月、快照模型提前 30 天公布下线。截至 2026-08-30，`qwen3.7-flash` 未出现在任何下线公告里：最近一个批次 2026-10-10 的六条公告已逐条人工核对，下线的是 qwen3 世代及更早的模型（qwen3-max、qwen3-vl-flash、qwen3-coder-plus、qwen-turbo 等）和语音系列，阿里云给出的推荐替换模型正是 qwen3.6/3.7 系列。

参考：[OpenRouter 的 Qwen3.7 Flash 模型页](https://openrouter.ai/qwen/qwen3.7-flash) 与 [API 参数页](https://openrouter.ai/qwen/qwen3.7-flash/apps)。
