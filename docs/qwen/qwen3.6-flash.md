# Qwen3.6 Flash 集成说明

更新日期：2026 年 8 月 2 日

词鲸当前通过 OpenRouter 使用模型标识 `qwen/qwen3.6-flash`，用于词义中文补充、阅读内查词和个性化双语短文生成。模型不直接暴露给 iOS 或 Chrome 扩展；所有调用都发生在已认证的 Supabase Edge Functions 中。

OpenRouter 当前将该模型描述为 Qwen 3.6 系列的快速模型，并列出文本、图像、视频输入和 1M 上下文能力。词鲸只使用文本聊天补全和结构化 JSON 输出，不依赖多模态或超长上下文；供应商能力、路由、价格和可用性可能变化，发布前应以 [OpenRouter 模型页](https://openrouter.ai/qwen/qwen3.6-flash) 为准。

## 配置

根目录 `.env`：

```dotenv
OPENROUTER_API_KEY=your_key_here
OPENROUTER_MODEL=qwen/qwen3.6-flash
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

参考：[OpenRouter 的 Qwen3.6 Flash 模型页](https://openrouter.ai/qwen/qwen3.6-flash) 与 [API 参数页](https://openrouter.ai/qwen/qwen3.6-flash/apps)。
