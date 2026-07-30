# Supabase 数据库迁移指南

本文说明词鲸如何创建、验证和发布 `supabase/migrations/` 中的 PostgreSQL 迁移。仓库采用按时间排序的命令式 SQL 迁移；迁移文件是数据库结构的唯一版本记录。

## 基本原则

- 已在共享、测试或生产环境执行过的迁移不可修改、重命名或重新排序；用新的前向迁移修正。
- 迁移必须同时考虑表结构、约束、索引、RLS、授权、函数、触发器和已有数据。
- 所有用户业务表必须启用 RLS，并用 `auth.uid()` 或等价且经审查的规则隔离用户。
- 不把生产用户数据、邮箱、访问令牌或 secret 写入迁移、`seed.sql`、测试日志或示例。
- `db reset` 默认重建本地数据库；`db reset --linked` 会破坏远程数据库，生产环境禁止使用。

## 1. 同步并建立基线

```bash
./scripts/supabase.sh start
./scripts/supabase.sh db reset
./scripts/supabase.sh migration list
```

`db reset` 会销毁本地数据，按文件名顺序重放全部迁移，然后执行 `supabase/seed.sql`。开始变更前先确保主分支的完整迁移链可以从空库重建。

如果接手的远程项目存在 Dashboard 中直接创建、但仓库没有的结构，先关联正确的非生产环境，再执行 `db pull` 建立基线。检查生成 SQL，特别留意意外的 `DROP`、扩展、授权和 `auth`/`storage` 结构；不要未经审查直接提交或推送。

## 2. 创建迁移

```bash
./scripts/supabase.sh migration new add_descriptive_name
```

在新文件中编写最小、明确的 SQL。命名使用小写 snake_case，描述结果而不是实现过程。常见安全写法包括：

- 新增可空列，回填已有行，再增加默认值或 `not null`；
- 大表索引和数据回填评估锁表时间，必要时拆成多个发布步骤；
- 替换函数时完整写出 `security invoker/definer` 与固定 `search_path`；
- 新表同时写 RLS、policy、所需 grant、索引和 `on delete` 行为；
- 破坏性删除先确认客户端已停止读取旧字段，并单独安排后续迁移。

不要只在本地 Studio 中保留修改。若使用 Studio 原型，应通过 `db diff` 生成候选 SQL并逐行审查：

```bash
./scripts/supabase.sh db diff --schema public -f describe_change
```

本仓库没有 `supabase/schemas/` 声明式源文件，因此以本地数据库与已有迁移的差异为准；生成结果仍可能包含噪声或意外授权。

## 3. 本地验证

```bash
./scripts/supabase.sh db reset
make functions
# 另一个终端
make smoke
```

至少检查：

1. 从空库重放成功且 `seed.sql` 无敏感数据；
2. 未登录请求无法读取或修改业务数据；
3. 用户 A 不能读取、更新或删除用户 B 的行；
4. RPC 只授权给预期角色，`security definer` 函数不会绕过所有者检查；
5. 外键级联与账号删除符合预期；
6. 旧客户端仍能在迁移后的结构上完成关键路径；
7. Edge Functions 的查询、返回字段和 JSON Schema 已同步更新。

涉及 AI 时，普通 `make smoke` 不产生模型费用；只有需要验证真实模型契约时才运行 `node scripts/smoke-test.mjs --ai`。

## 4. 发布到远程环境

首次关联项目：

```bash
./scripts/supabase.sh login
./scripts/supabase.sh link --project-ref <project-ref>
```

每次发布都先确认关联项目和迁移历史，再预览：

```bash
./scripts/supabase.sh projects list
./scripts/supabase.sh migration list
./scripts/supabase.sh db push --dry-run
```

先发布测试/预发布环境并完成冒烟测试，确认备份和维护窗口后再执行生产推送：

```bash
./scripts/supabase.sh db push
make production-audit
make production-smoke
```

`db push` 只执行远程迁移历史中尚未记录的本地文件。生产环境不要使用 `--include-seed`，也不要使用 `db reset --linked`。

若数据库变更伴随函数代码或 secret 更新，推荐顺序是：兼容性数据库迁移 → secrets → 向后兼容的 Edge Functions → 客户端。删除旧列或旧行为应等确认旧客户端退出使用后再做。

## 5. 故障与修复

迁移失败时停止后续发布，保存完整错误、目标项目、已成功步骤和数据库备份状态。不要通过删除迁移文件或手工改 `supabase_migrations.schema_migrations` 掩盖失败。

- 尚未进入共享环境：可修正新迁移后重新 `db reset`；
- 已进入共享或生产环境：创建新的前向修复迁移；
- 只有迁移历史与真实结构明确不一致、且已人工核验原因时，才考虑 `migration repair`；
- 涉及数据删除或不可逆转换时，从经过验证的备份恢复，或执行事先准备的补偿迁移。

## 检查清单

- [ ] 新迁移文件名唯一且顺序正确
- [ ] 完整 `db reset` 成功
- [ ] RLS、policy、grant 与跨用户隔离已验证
- [ ] 已评估已有数据、锁表、旧客户端与回滚/修复路径
- [ ] `db push --dry-run` 只包含预期迁移
- [ ] 测试环境与生产环境的项目引用已分别核对
- [ ] 相关 `supabase/README.md`、客户端、函数和测试已同步

参考：[Supabase Local development workflow](https://supabase.com/docs/guides/local-development/cli-workflows) 与 [Database migrations](https://supabase.com/docs/guides/local-development/database-migrations)。
