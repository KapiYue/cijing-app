# 第三方词典、AI 输出与网页语境处理记录

更新日期：2026 年 8 月 2 日

本文记录“词鲸背单词”送审前对第三方词典、AI 输出和网页语境的技术与条款核对。它用于维护和复核，不替代专业法律意见；上游条款或模型发生变化时必须重新检查。

## Free Dictionary API

词鲸通过 `api.dictionaryapi.dev` 获取英文释义、音标和部分发音。接口响应会为词条提供 `sourceUrls` 与 `license`，并可为每个发音提供独立的 `sourceUrl` 与 `license`。当前常见词条源自 Wiktionary，采用 CC BY-SA 3.0；发音可能采用 CC BY、CC BY-SA 的其他版本，不能用词条许可代替发音许可。

项目采取以下约束：

1. 只有同时提供可访问来源 URL 和内容许可的词条才会进入查词结果；
2. 只有同时提供来源 URL 和独立许可的真人发音才会使用，否则回退到系统语音；
3. Edge Function 把词条、词条许可、来源、发音来源和发音许可一并返回；
4. 查词缓存与个人词库保留许可元数据；
5. iOS 查词页、阅读查词页、个人词条详情和 Chrome 查词卡均提供逐条来源与许可链接；
6. App“关于词鲸 → 第三方内容与许可”和官网 `/credits` 提供统一说明；
7. 由受 CC BY-SA 词条改编的释义继续标明原来源及同方式共享许可。

Free Dictionary API 服务端项目自身的 GPL-3.0 许可与接口返回内容的 Creative Commons 许可不是同一许可链，不得混用。

## OpenRouter 与 Qwen

生产配置模型为 `qwen/qwen3.6-flash`，所有请求由已认证的 Supabase Edge Functions 发出。2026 年 8 月 2 日核对结果：

- OpenRouter 条款把输入和输出合称 User Content；输入权利仍归输入者，输出权利由具体 Model Terms 决定；
- OpenRouter 要求输入者拥有提交输入所需的权利，并要求同时遵守模型供应商条款；
- OpenRouter 的数据控制支持 `provider.data_collection = "deny"`，项目已在每次请求中强制设置，拒绝会收集请求用于训练的端点；
- Qwen3.6 Flash 当日不在 OpenRouter 公布的 ZDR 端点列表中，因此项目没有虚构“零保留”承诺；隐私政策继续披露上游处理与可能的跨境处理；
- OpenRouter 当日模型页只显示 Alibaba 单一提供方，未完整展示可独立归档的输出权利条款。项目因此只在语言学习功能中展示输出，不宣称人工创作、独占权利或无侵权保证，并保留 AI 内容提示。

换模前必须重新保存模型页、Model Terms、数据政策和地区可用性证据。若无法确认商业展示输出的范围，暂停该模型上线，而不是沿用本记录。

## 网页语境

Chrome 扩展只在用户主动选中英文单词并发起查询时读取附近文本。当前实现先在本地定位包含该词的句子，再只向服务端发送该句，最长 600 字符；不发送所在段落、页面正文、Cookie 或完整浏览历史。

“保存网页语境”控制是否把当前句子、页面标题和 URL 写入个人词库。“隐私模式”会在发出请求前同时清空句子、标题和 URL。用户条款要求仅在有权阅读和处理的页面使用扩展，不得提交侵权或侵犯他人隐私的内容。

## 发布前复核

- 运行扩展测试、iOS 构建和生产冒烟测试；
- 抽查至少三个带不同发音许可的词条，确认来源与许可链接可打开；
- 确认生产 `OPENROUTER_MODEL` 仍为已核对模型，且请求仍设置 `data_collection = "deny"`；
- 确认 OpenRouter 账号没有开启输入/输出日志或训练授权；
- 模型、词典接口、数据字段或上游条款变化后更新本记录、隐私政策、使用条款和 App 内说明。

## 参考

- [Free Dictionary API](https://dictionaryapi.dev/)
- [Creative Commons Attribution-ShareAlike 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
- [OpenRouter Terms of Service](https://openrouter.ai/terms)
- [OpenRouter Data Collection](https://openrouter.ai/docs/guides/privacy/data-collection)
- [OpenRouter Provider Routing](https://openrouter.ai/docs/guides/routing/provider-selection)
- [OpenRouter Qwen3.6 Flash](https://openrouter.ai/qwen/qwen3.6-flash)
