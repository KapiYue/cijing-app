# 词鲸背单词

词鲸背单词把真实英文阅读、个人词库、AI 分级阅读和间隔复习连成一个学习闭环。项目参考 `miaoji` 的 iOS 工程边界组织：

```text
.
├── client/      # SwiftUI iOS App（首页、词库、查词、设置及完整学习流）
├── extension/   # Chrome Manifest V3 双击取词与收藏
├── server/      # 可信 Flask 服务、健康检查与未来特权任务
├── supabase/    # Postgres、RLS、RPC、种子数据与 Edge Functions
├── .env.example # 可提交的完整变量清单
├── .env         # 唯一本地配置源，必须被 Git 忽略
└── docs/        # 架构、开发和生产部署说明
```

客户端采用四个独立 `NavigationStack`，根 Tab 为首页、词库、查词和设置。视觉令牌、间距、卡片、悬浮 Tab Bar 和页面状态对照 `deliverables/CiJingApp-Interactive-Prototype 5/` 实现。

## 快速开始

```bash
cp .env.example .env
# 编辑 .env，填写当前环境的 Supabase 与 OpenRouter 变量
make config

./scripts/supabase.sh start
./scripts/supabase.sh db reset
make functions
```

然后使用 Xcode 打开 `client/CiJing.xcodeproj`，选择 `CiJing` scheme 和 iPhone 模拟器运行。安装到设备后的产品名为“词鲸背单词”。Chrome 扩展可在 `chrome://extensions` 通过“加载已解压的扩展程序”载入 `extension/`。

本地开发见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)，架构见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，生产变量和部署顺序见 [docs/PRODUCTION.md](docs/PRODUCTION.md)。

## 验证

```bash
make config-check
make extension-test
make server-test
make ios-build
```
