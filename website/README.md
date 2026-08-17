# 词鲸官网静态页面

本目录是 `cijing.joy-coder.com` 的静态站点产物，用于 App Store Connect 的隐私政策与支持 URL，并与 `joy-coder.com` 网站 ICP（`浙ICP备2026055717号-2`，服务名称「个人应用使用说明」）共用备案。

- `/`：政策与支持入口，标题 `个人应用使用说明｜词鲸背单词`
- `/privacy`：隐私政策，`https://cijing.joy-coder.com/privacy`
- `/credits`：第三方内容与许可，`https://cijing.joy-coder.com/credits`
- `/support`：支持中心与使用条款，`https://cijing.joy-coder.com/support`

内容源是 [`docs/privacy-policy.md`](../docs/privacy-policy.md)、[`docs/terms-of-service.md`](../docs/terms-of-service.md)、[`docs/third-party-content-and-ai-compliance.md`](../docs/third-party-content-and-ai-compliance.md) 与 [`docs/support.md`](../docs/support.md)。修改公开内容时必须在同一个提交中同步对应 HTML。

## 部署

Nginx 站点配置在 [`deploy/nginx/cijing.conf`](../deploy/nginx/cijing.conf)。服务器目录、证书路径、上传方式与回滚步骤属于维护者本地材料，不随仓库发布。

上线前核对：

1. `website/` 全量同步到站点目录，**不要带入本 README**；
2. `cijing.conf` 已启用且 `sudo nginx -t` 通过；
3. TLS 覆盖 `cijing.joy-coder.com`；
4. DNS 中 `cijing` A 记录指向服务器公网 IP；
5. 无痕访问 `/privacy`、`/support` 返回 200，页脚同时展示网站 ICP `浙ICP备2026055717号-2`、App ICP `浙ICP备2026055717号-3A` 与 `浙公网安备33010502013311号`（含图标与查询链接）；
6. `/assets/police-filing-icon.png` 返回 200，页脚图标不是裂图。

**两类 ICP、两类公安号不要混用**：页脚必须保留网站 ICP `浙ICP备2026055717号-2`，并并列展示 App ICP `浙ICP备2026055717号-3A`。`浙公网安备33010502013311号` 是 **网站** 公安联网备案号。`joy-coder.com`、`www` 与 `cijing` 同属一条网站备案记录，本站依法必须展示该编号、图标与查询链接。**APP** 公安联网备案是另一件事，已于 2026-08-13 提交、状态审核中；取得 APP 公安编号前，App 内不得展示网站公安号，也不得复用妙记的 APP 备案信息。
