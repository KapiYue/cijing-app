# Supabase 架构、开发与生产运维

本目录是词鲸的主要后端：PostgreSQL 迁移、Row Level Security（RLS）、RPC、种子说明和 Deno Edge Functions。发布版 iOS App 与 Chrome 扩展直接使用 Supabase Auth/PostgREST；真机本地联调版 iOS 会先经过 Mac 上的 Flask 8000 透明转发。需要 AI 或管理员权限的操作经 Edge Functions 完成。

```text
iOS App ─────┐
             ├─ Auth / PostgREST ── PostgreSQL + RLS + RPC
Chrome 扩展 ─┘                 └──── Edge Functions ── OpenRouter / Qwen
```

Flask 只进入真机本地联调请求链路，不进入最终 App Store Release 包；它保留客户端 publishable key、用户会话和 Supabase RLS 边界。其边界和启动方式见 [`server/README.md`](../server/README.md)。

## 目录与职责

```text
supabase/
├── config.toml          # 本地 Supabase、Auth 与函数运行配置
├── migrations/          # 按时间顺序执行的数据库变更
├── seed.sql             # 本地种子说明；不含生产用户数据
└── functions/
    ├── _shared/         # JWT、CORS、公开词典和 OpenRouter 适配
    ├── lookup-word/
    ├── explain-reading-word/
    ├── generate-reading/
    └── delete-account/
```

四个函数都在业务代码中调用 `requireUser` 校验 Bearer token。`config.toml` 中的 `verify_jwt = false` 只关闭网关的旧式 JWT 校验，以兼容当前 publishable key；它不代表允许匿名访问。新增函数必须显式选择并记录自己的认证边界。

## 数据与安全边界

主要表如下：

| 表 | 内容 |
| --- | --- |
| `profiles` | 昵称、每日目标、阅读与语音偏好 |
| `words` / `word_contexts` | 个人词库、首个及后续网页语境 |
| `review_events` | 0–5 质量分、练习类型、答案与响应时间 |
| `reading_sessions` | AI 短文、目标词、难度、进度与完成时间 |
| `practice_attempts` / `voice_attempts` | 阅读练习与跟读结果的数据结构 |
| `daily_activity` | 按日聚合的学习活动 |
| `lexicon_cache` | 按用户、词形与上下文哈希隔离的查词缓存 |

所有业务表都启用 RLS，并用 `auth.uid()` 约束所有者。RPC 使用 `security invoker`，只向 `authenticated` 角色授权。业务表引用 `auth.users(id) on delete cascade`；`delete-account` 只从当前有效令牌取得用户 ID，客户端不能指定要删除的其他账号。

客户端只持有 Supabase URL、publishable key 与当前用户会话。`SUPABASE_SECRET_KEY`、托管环境提供的 service-role key 和 `OPENROUTER_API_KEY` 不得进入 iOS、扩展、日志或 Git。根目录 `.env` 是唯一的本地配置源，`.env.example` 是唯一可提交的变量模板。

### 学习调度

`apply_review` 根据 0–5 质量分更新 `strength`、`ease_factor`、`interval_days`、`repetitions`、`lapses` 和 `due_at`：

- 0–2：记为遗忘，回到短间隔并进入 `weak`；
- 3：困难，较慢增加间隔；
- 4：正常，按易度系数增加；
- 5：轻松，在正常间隔上额外放大。

`get_daily_plan` 汇总到期、薄弱与新词；`get_learning_targets` 按薄弱、到期、新词和学习中排序。AI 阅读复用同一批目标词，完成阅读和练习后再写回活动与调度数据。

### AI 与缓存

`lookup-word` 和 `explain-reading-word` 先读取 Free Dictionary API 的公开发音/英文释义，再由 OpenRouter 补充中文与语境解释；公开词典不可用时按能力降级。`generate-reading` 使用用户词库中的目标词生成结构化双语短文。

- `lexicon_cache` 按用户、规范化词形与上下文哈希缓存，默认 90 天到期；
- `reading_sessions.cache_key` 由目标词、主题、文体与难度生成；
- 显式“重新生成”跳过短文缓存；改变主题、文体或难度会得到新键；
- AI 输出必须通过严格 JSON Schema 和本地类型检查；第一次不合规时只允许一次纠正请求。

默认模型及响应约束见 [`docs/qwen/qwen3.7-flash.md`](../docs/qwen/qwen3.7-flash.md)。

## 本地开发

前置环境：Docker Desktop、Node.js 20+。`scripts/supabase.sh` 会下载并缓存仓库固定的 Supabase CLI 版本。

```bash
cp .env.example .env
# 在根目录 .env 填写当前环境变量
make config

./scripts/supabase.sh start
./scripts/supabase.sh db reset
make functions
```

`db reset` 会销毁并重建本地数据库，依次执行全部迁移及 `seed.sql`；不要对有价值的远程项目使用带 `--linked` 的 reset。运行 `./scripts/supabase.sh status` 可查看本地 API、Studio 和兼容 key。把同一实例的 URL 与 publishable/anon key 填入 `.env` 后重新运行 `make config`。

Edge Functions 需要：

```dotenv
OPENROUTER_API_KEY=your_key_here
OPENROUTER_MODEL=qwen/qwen3.7-flash
```

`make functions` 会从根 `.env` 读取这两项，通过权限为 `0600` 的系统临时文件传给本地 Edge Runtime，并在进程结束后删除临时文件。模型可以换成项目允许且兼容严格 JSON Schema 的 OpenRouter 模型；代码会拒绝 `openai/`、`anthropic/` 和 `google/` 前缀。

数据库变更必须通过新迁移完成，具体流程见 [`docs/supabase-migration-guide.md`](../docs/supabase-migration-guide.md)。不要修改已经在共享或生产环境应用过的迁移。

## 生产配置

所有人工配置先写入本机根 `.env`，再由脚本生成或推送到对应运行时：

| 变量 | 使用方 | 可进入客户端 |
| --- | --- | --- |
| `SUPABASE_URL` | iOS、扩展、Flask、Edge Functions | 是 |
| `SUPABASE_PUBLISHABLE_KEY` | iOS、扩展 | 是 |
| `OPENROUTER_API_KEY` | Edge Function secret | 否 |
| `OPENROUTER_MODEL` | Edge Function 配置 | 否（当前无需客户端读取） |
| `SUPABASE_SECRET_KEY` | Flask 托管环境 | 否 |
| `PORT` | Flask 容器 | 不适用 |
| `SUPABASE_ANON_KEY` | legacy/local 兼容项 | 仅兼容场景 |
| `SUPABASE_PUBLISHABLE_KEYS` | Supabase 托管运行时兼容项 | 否 |

托管的 Edge Functions 会自动获得项目 URL 与平台密钥。项目兼容当前 publishable key、平台注入的 key 集合和本地 CLI 的 legacy anon key；不要为了函数校验而手工复制客户端 key 到 secrets。

### 上线顺序

1. 确认当前关联的是目标项目：`./scripts/supabase.sh projects` 与 `./scripts/supabase.sh migration list`。
2. 将 `.env` 切换为生产值，运行 `make config` 和 `make config-check`；确认 URL 为预期的 HTTPS 地址。
3. 运行 `./scripts/supabase.sh db push --dry-run` 预览，再运行 `./scripts/supabase.sh db push` 应用尚未执行的迁移。
4. 运行 `make edge-secrets` 推送 OpenRouter 配置。脚本使用临时 `0600` 文件，完成后自动删除。
5. 部署 `lookup-word`、`explain-reading-word`、`generate-reading` 与 `delete-account` 四个 Edge Functions。
6. 在 Supabase Dashboard 的 `Authentication → Sign In / Providers → Email` 中核对 Email Provider、注册、邮箱确认和密码策略。生产环境必须启用邮箱确认并配置确认邮件模板与跳转地址；客户端会拒绝注册后直接建立会话，防止配置回退时绕过验证邮件。
7. 如需 Flask 健康检查服务，按 [`server/README.md`](../server/README.md) 独立部署；它使用 server-only secret key。
8. 使用 Release 配置归档 iOS App；生产包不得包含局域网 HTTP URL 或任何 secret key。

部署函数示例：

```bash
for name in lookup-word explain-reading-word generate-reading delete-account; do
  ./scripts/supabase.sh functions deploy "$name"
done
```

### Xcode Cloud

在 Xcode Cloud workflow 的 Environment Variables 中配置公开的 `SUPABASE_URL` 与 `SUPABASE_PUBLISHABLE_KEY`。`client/ci_scripts/ci_post_clone.sh` 会生成被 `.gitignore` 排除的 `GeneratedClientConfig.swift`；变量缺失或格式错误时会提前失败，无需提交生成文件。

## 验证与回滚

本地完整验证：

```bash
make config-check
./scripts/supabase.sh db reset
make functions
# 另一个终端
make smoke
```

追加 `node scripts/smoke-test.mjs --ai` 会产生一次真实 OpenRouter 请求。生产部署后依次运行：

```bash
make production-audit
make production-smoke
make delete-account-smoke
```

生产验收脚本使用独立的 `cijing_e2e_*` 临时账号，并在结束时删除；业务数据通过外键级联清理。数据库迁移没有通用自动回滚：出现问题时优先停止继续发布，保留日志和备份，编写新的前向修复迁移，再按 dry-run、测试环境、生产环境的顺序执行。

## 参考资料

- [Supabase Local development workflow](https://supabase.com/docs/guides/local-development/cli-workflows)
- [Supabase database migrations](https://supabase.com/docs/guides/local-development/database-migrations)
- [Supabase Edge Functions development environment](https://supabase.com/docs/guides/functions/development-environment)
