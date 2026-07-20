# 架构

```text
client/CiJing.xcodeproj + client/CiJing (SwiftUI) ─┐
                       ├─ Supabase Auth / PostgREST / Realtime
extension/ (Chrome) ───┘                 │
                                         ├─ PostgreSQL + RLS + RPC
                                         └─ Edge Functions ── OpenRouter (Qwen)

server/ (Flask) ── trusted health/ops boundary; no client secrets
```

## 安全边界

- 根目录 `.env` 是唯一配置源；`.env.example` 只保存变量名、安全示例和说明。
- iOS、扩展与 Edge Functions 的构建配置由 `.env` 生成，生成文件不进入 Git。
- 客户端只持有本地 Supabase 的匿名公钥与用户会话，不含 OpenRouter 密钥。
- 所有用户数据表都启用 RLS，按 `auth.uid()` 隔离。
- AI 调用由 Edge Function 校验用户 JWT 后执行，并写入用户级缓存。
- 扩展仅在用户双击英文词时读取当前句子/段落；收藏前不上传完整页面。

## 学习调度

每个单词保存 `strength`、`ease_factor`、`interval_days`、`repetitions`、`lapses` 与 `due_at`。数据库函数 `apply_review` 根据 0–5 质量分更新状态和下次复习时间：

- 0–2：遗忘，回到短间隔并记为薄弱。
- 3：困难，缓慢增加间隔。
- 4：正常，按易度系数增加。
- 5：轻松，额外放大间隔。

首页 RPC `get_daily_plan` 会混合逾期旧词、薄弱词和新词。AI 阅读使用同一批目标词生成自然多段短文，完成练习后将结果回写到调度器。

## AI 缓存

- `lexicon_cache`：按词形与上下文哈希缓存解释。
- `reading_sessions.cache_key`：按目标词、难度、主题、风格缓存短文。
- 再生成会显式跳过缓存；调整难度/主题会产生新的缓存键。
