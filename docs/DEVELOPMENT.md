# 本地开发

## 前置环境

- macOS + Xcode 16 或更新版本
- Docker Desktop
- Node.js 20+
- Supabase CLI（仓库脚本会从官方 GitHub Release 下载并缓存已固定版本）

## 1. 启动本地 Supabase

```bash
cp .env.example .env
# 编辑根目录 .env，填写当前环境的全部变量
make config

./scripts/supabase.sh start
./scripts/supabase.sh db reset
make functions
```

根目录 `.env` 是项目唯一配置源，已被 `.gitignore` 排除；可提交的变量清单只有 [`.env.example`](../.env.example)。`make config` 会为 iOS 和 Chrome 扩展生成构建产物，这些产物同样不会被 Git 跟踪；`make functions` 从根 `.env` 读取 Edge Functions 所需变量，通过权限为 `0600` 的系统临时文件交给 Supabase CLI，进程结束后自动删除。

执行 `./scripts/supabase.sh status` 可查看本地 URL 与兼容 key；填入 `.env` 后运行：

```bash
make config
```

### 真机调试地址

真机中的 `127.0.0.1` 指向 iPhone 自身。先查看 Mac 的 Wi-Fi 局域网 IP：

```bash
ipconfig getifaddr en0
```

假设输出为 `192.168.1.20`，可用一条命令更新共同配置并重新生成两端文件：

```bash
node scripts/generate-config.mjs --url http://192.168.1.20:54321
```

然后重新构建 iOS App，并在 `chrome://extensions` 中刷新扩展。iOS 和扩展中的连接页只负责显示与测试，不再保存独立覆盖值。iPhone 与 Mac 需处于同一局域网，且 macOS 防火墙不能阻止 Docker/Supabase 端口；模拟器可以继续使用 `127.0.0.1`。

## 2. 配置 OpenRouter

根目录 `.env`：

```dotenv
OPENROUTER_API_KEY=your_key_here
OPENROUTER_MODEL=qwen/qwen3.6-flash
```

模型可替换为任何 OpenRouter 上可用的非 OpenAI、Anthropic、Google 模型。Edge Function 强制拒绝这三个供应商前缀。

## 3. 运行 Chrome 扩展

1. 打开 `chrome://extensions`。
2. 打开“开发者模式”。
3. 点击“加载已解压的扩展程序”，选择仓库内的 `extension/`。
4. 点击工具栏“词鲸背单词”图标，注册账号或登录。
5. 在英文网页双击单词。卡片支持查询、发音和收藏；设置页可查看并测试当前 `.env` 生成的连接。

修改扩展后，在扩展管理页点击刷新。

## 4. 运行 iOS App

1. 用 Xcode 打开 `client/CiJing.xcodeproj`。
2. 选择 iOS 17+ 模拟器。
3. 运行 `CiJing` scheme。
4. 使用与 Chrome 扩展相同的邮箱登录。

麦克风与语音识别权限仅在进入跟读模式时请求。

## 5. 验证

```bash
make config-check
node --test extension/tests/*.test.mjs
find extension -name '*.js' -print0 | xargs -0 -n1 node --check
xcodebuild -project client/CiJing.xcodeproj -scheme CiJing \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath client/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Supabase 运行后可执行跨端 API 冒烟测试；追加 `--ai` 会真实调用一次 OpenRouter：

```bash
node scripts/smoke-test.mjs
node scripts/smoke-test.mjs --ai
```
