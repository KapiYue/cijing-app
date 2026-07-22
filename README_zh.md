# 词鲸背单词 · CiJing

<p align="center">
  <img src="client/CiJing/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" alt="词鲸背单词图标">
</p>

<p align="center">
  把真实阅读中遇见的单词，变成个人词库、AI 分级短文和可持续的间隔复习。
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="docs/DEVELOPMENT.md">开发指南</a> ·
  <a href="docs/ARCHITECTURE.md">架构说明</a> ·
  <a href="docs/PRODUCTION.md">生产部署</a> ·
  <a href="docs/APP_STORE_CHECKLIST_zh.md">App Store 清单</a>
</p>

<p align="center">
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-6f49cc">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-f09b62">
  <img alt="Supabase" src="https://img.shields.io/badge/后端-Supabase-3ecf8e">
  <img alt="MIT License" src="https://img.shields.io/badge/许可证-MIT-7252cc">
</p>

## 页面展示

软件只有四个一级页面。以下截图使用了接近真实用户的丰富演示数据，直观展示完整学习状态。

<table>
  <tr>
    <td align="center"><strong>首页</strong><br><sub>今日计划、可持久化的短文记录与练习入口</sub></td>
    <td align="center"><strong>词库</strong><br><sub>学习状态、熟练度、复习时间与语境单词</sub></td>
  </tr>
  <tr>
    <td><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.9/01-home.jpg" alt="词鲸首页"></td>
    <td><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.9/02-library.jpg" alt="词鲸词库"></td>
  </tr>
  <tr>
    <td align="center"><strong>查词</strong><br><sub>释义、发音、例句与一键收藏</sub></td>
    <td align="center"><strong>设置</strong><br><sub>学习偏好、隐私管理、缓存与账户</sub></td>
  </tr>
  <tr>
    <td><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.9/03-lookup.jpg" alt="词鲸查词"></td>
    <td><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.9/04-settings.jpg" alt="词鲸设置"></td>
  </tr>
</table>

## 核心能力

- 通过 Chrome Manifest V3 扩展收藏网页单词和首次出现的语境。
- 维护用户私有词库、学习状态、笔记、熟练度和下一次复习时间。
- 从薄弱词、到期词和新词中选择目标词，生成自然连贯的双语分级短文。
- 每篇生成内容都写入 `reading_sessions`，重启 App 或重新登录后仍可从首页继续阅读。
- 使用熟练度、易度系数、间隔、遗忘次数与到期时间安排复习。
- 支持系统发音、跟读和基于短文的练习闭环。
- 所有用户数据均由 Supabase Row Level Security 按账号隔离。

## 仓库结构

```text
.
├── client/      # SwiftUI iOS App
├── extension/   # Chrome 双击查词与收藏扩展
├── supabase/    # PostgreSQL 迁移、RLS、RPC 与 Edge Functions
├── server/      # 可信 Flask 服务边界与健康检查
├── scripts/     # 配置、审计与冒烟测试脚本
├── docs/        # 开发、架构、生产部署与商店素材
└── website/     # 对外托管的隐私政策与支持页面
```

iOS App 和扩展通过 Supabase Auth 与 PostgREST 共享账号和学习数据；通过身份校验的 Edge Functions 调用所配置的 OpenRouter 模型生成词义解释和分级短文。服务端密钥与 AI 服务密钥不会进入客户端安装包。

## 快速开始

需要 macOS、Xcode 16 或更新版本、Node.js 20+、Docker Desktop 和 Chrome。

```bash
cp .env.example .env
# 在 .env 中填写当前环境变量
make config

./scripts/supabase.sh start
./scripts/supabase.sh db reset
make functions
```

用 Xcode 打开 `client/CiJing.xcodeproj`，选择 `CiJing` scheme 和 iOS 17+ 模拟器运行。Chrome 扩展可在 `chrome://extensions` 中选择“加载已解压的扩展程序”，然后载入 `extension/`。

## 验证

```bash
make config-check
make extension-test
make server-test
make ios-build
```

本地 Supabase 启动后可运行 `make smoke` 验证跨端 API 流程；生产部署完成后可运行 `make production-audit` 与 `make production-smoke`。

## 参与贡献与安全

提交贡献前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。发现安全问题时请按照 [SECURITY.md](SECURITY.md) 私下报告，不要创建公开 Issue。

本项目采用 [MIT License](LICENSE)。
