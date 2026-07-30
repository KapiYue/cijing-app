# 词鲸官网静态页面

本目录准备了未来供 App Store Connect 使用的公开页面。当前域名与 App 备案仍在办理，页面尚未作为正式公开 URL 交付，App Store Connect 先保留 `【备案中，URL 待上线后回填】`：

- `/`：政策与支持入口
- `/privacy`：隐私政策，对应 `https://cijing.joy-coder.com/privacy`
- `/support`：支持中心，对应 `https://cijing.joy-coder.com/support`

内容源是 [`docs/privacy-policy.md`](../docs/privacy-policy.md)、[`docs/terms-of-service.md`](../docs/terms-of-service.md) 与 [`docs/support.md`](../docs/support.md)。修改公开内容时必须在同一个提交中同步对应 HTML；HTML 文件顶部保留来源注释，便于检查漂移。

页面为纯静态 HTML/CSS，可部署到任意静态托管或当前备案主体的 Web 服务。上线前需要：

1. 完成适用的 ICP 备案流程；
2. 为 `cijing.joy-coder.com` 添加正确的 DNS 记录；
3. 将 Web 根目录指向本目录并启用 HTTPS；
4. 验证两个 URL 在未登录、无 Cookie 的浏览器中可直接访问；
5. 每次 App 数据处理能力、第三方服务或账号删除流程变化时，同步更新 Markdown、网页与 App 内法律说明。
