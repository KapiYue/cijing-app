# 词鲸官网静态页面

本目录准备了 App Store Connect 使用的两个公开页面：

- `/privacy`：隐私政策，对应 `https://cijing.joy-coder.com/privacy`（`/` 同时保留政策页面）
- `/support`：支持中心，对应 `https://cijing.joy-coder.com/support`

页面为纯静态 HTML/CSS，可部署到任意静态托管或当前备案主体的 Web 服务。上线前需要：

1. 完成适用的 ICP 备案流程；
2. 为 `cijing.joy-coder.com` 添加正确的 DNS 记录；
3. 将 Web 根目录指向本目录并启用 HTTPS；
4. 验证两个 URL 在未登录、无 Cookie 的浏览器中可直接访问；
5. 每次 App 数据处理能力变化时同步更新网页与 App 内法律说明。
