# 生产环境配置

项目按 `miaoji` 的边界拆为三层：

- `client/`：SwiftUI iOS 客户端，只包含 Supabase URL 与 publishable key。
- `supabase/`：Postgres、RLS、RPC 与 Edge Functions；OpenRouter 密钥只存在于 Edge Function secrets。
- `server/`：可信 Flask 运行时与健康检查，使用 server-only secret key；当前不在用户请求链路中。

## 需要填写的变量

所有变量只填写在根目录 `.env`；[`.env.example`](../.env.example) 是唯一可提交的变量模板。

| 变量 | 使用方 | 是否可公开 |
| --- | --- | --- |
| `SUPABASE_URL` | iOS、扩展、服务端、Edge Functions | 是 |
| `SUPABASE_PUBLISHABLE_KEY` | iOS、扩展、Edge Functions | 是 |
| `OPENROUTER_API_KEY` | Supabase Edge Function secret | 否 |
| `OPENROUTER_MODEL` | Supabase Edge Function 配置 | 是 |
| `SUPABASE_SECRET_KEY` | Flask 托管平台环境 | 否 |
| `PORT` | Flask 容器 | 是 |
| `SUPABASE_ANON_KEY` | legacy/local Supabase 兼容项 | 是 |
| `SUPABASE_PUBLISHABLE_KEYS` | Supabase 托管环境自动注入的兼容项 | 是 |

客户端不得出现 `SUPABASE_SECRET_KEY` 或 `OPENROUTER_API_KEY`。

## 上线顺序

1. 复制 `.env.example` 为 `.env`，填写生产变量并运行 `make config`。
2. 执行 `supabase db push --project-ref <project-ref>` 应用迁移。
3. 执行 `make edge-secrets`，脚本从根目录 `.env` 读取 OpenRouter 变量，通过权限为 `0600` 的系统临时文件推送到已关联的 Supabase 项目，并立即删除临时文件。
4. 部署四个 Edge Functions：`lookup-word`、`explain-reading-word`、`generate-reading`、`delete-account`。其中 `delete-account` 只接受当前登录用户的有效令牌，并使用托管环境自动注入的 service-role 权限删除该用户；客户端不能指定其他用户 ID。
5. 在 Supabase `Authentication → Sign In / Providers → Email` 中保持 Email Provider 与注册开启；第一版关闭 `Confirm email` 和 `Secure password change`，密码最小长度设置为 8。iOS 与 Chrome 扩展都直接使用用户填写的真实邮箱。两端已经兼容“注册后需确认邮箱”的响应，后续开启 `Confirm email` 时再配置邮件模板与跳转地址即可。
6. 如部署 Flask 服务，将 `.env` 中的 `SUPABASE_URL`、`SUPABASE_SECRET_KEY` 和 `PORT` 注入托管平台，使用 `server/Dockerfile` 构建。
7. 用 Release 配置归档 iOS App；生产包不依赖开发设置页中的本地覆盖值。

部署后先执行 `make production-audit` 核对表、RPC、认证策略和 Edge Functions，再执行
`make production-smoke` 跑邮箱注册、密码登录、词库、复习、AI 查词与 AI 阅读的端到端验收；
`make delete-account-smoke` 使用独立临时账号验证自助删除、删除后拒绝登录和 Auth 用户移除。
验收脚本使用独立的 `cijing_e2e_*` 邮箱，并在结束时删除该用户；所有业务数据依赖
`on delete cascade` 同步清理。

不得提交 `.env` 或生成后的 Swift/JavaScript 配置。

托管的 Edge Functions 会由 Supabase 注入项目 URL 与客户端 API key；项目同时兼容当前 publishable key、平台注入的 key 集合和本地 CLI 的 legacy anon key，无需手工把客户端 key 设为 Function secret。
