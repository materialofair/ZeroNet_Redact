# ZeroNet Redact 海外推广包

准备日期：2026-09-23。目标：海外英语用户；首轮零广告预算。状态：文案草稿，尚未发布、投稿或联系任何人。

## 定位与首轮实验

**Redact private details on your iPhone. Keep originals on your device.**

先争取需要分享截图、收据和 PDF 的 iPhone 用户。以一个真实操作演示吸引试用：导入含虚构邮箱的截图 → 识别并复核 → 遮挡 → 导出查看。视频功能作为后续内容，不把所有卖点堆进第一条帖子。

首轮成功标准是获取具体试用反馈并判断哪个渠道带来下载，不设没有依据的下载量承诺。每个平台单独记录曝光、点击、可归因下载和用户遇到的问题；没有统计权限的数据记为 unknown。

官网：https://zeronet-redact.materialofair.chatgpt.site/en/

下载：https://apps.apple.com/us/app/zeronet-redact-blur-censor/id6756290503

源码：https://github.com/materialofair/ZeroNet-Redact

## 发布口径

以当前官网、App Store 产品页及本地 PRODUCT.md 为依据。商店已显示 1.5.0，本地 CHANGELOG 仍标记 Unreleased；对外版本信息采用商店页面。

- 文件内容在设备本地处理，原文件无需上传；无需账号。
- 图片、PDF、视频；本地文字检测、手动遮挡、复核后导出。
- 免费试用有每日导出限制，一次性内购升级，无订阅。首轮不固定美元价格，以各地区商店为准。
- 可以介绍 PDF 遮挡区域下文字的移除，但不得承诺整个文档所有敏感信息都已消除。
- 不宣传“永不联网”：购买与恢复购买使用 Apple 服务。
- 不宣传“100% 自动识别”“绝对安全”或“不可恢复的所有文件”。识别结果和完整导出结果都需要复核。
- 不把视频手动框说成自动跟踪框；当前商店说明手动框位置固定。
- 不使用未经证实的用户量、评价、奖项或竞品比较。

## 1. X 首发帖

配一段实际 App 录屏，正文如下：

```text
I built ZeroNet Redact for iPhone and iPad: hide private details in screenshots, PDFs and videos without uploading your originals.

No account. No subscription. Try it free, then review your export before sharing.

https://zeronet-redact.materialofair.chatgpt.site/en/
```

### X 第二条：独立的 PDF 主题

```text
Sharing a PDF with private details?

ZeroNet Redact removes text beneath redacted areas on your iPhone or iPad. Check every page and review the exported copy before sending it.

https://zeronet-redact.materialofair.chatgpt.site/en/
```

## 2. Reddit 开发者介绍

适用：明确允许开发者自荐的社区或活动。不是批量群发模板。r/apple 当前仅周日允许 App 自荐，还要求过去一个月至少 5 次与自己 App 无关的真实参与、自荐比例不超过 10%；不符合就跳过，不通过突击评论凑资格。发布前再次核对规则和活动时间。

Title:

```text
I made an iPhone app for redacting screenshots, PDFs and videos on device
```

Body:

```text
I'm the developer of ZeroNet Redact, an iPhone and iPad app for preparing files before sharing them.

The workflow is simple: import a file, review the private details you want to hide, add covers, and inspect the exported copy. Content processing happens on your device without uploading your originals.

For screenshots, you can review detected phone numbers and email addresses or add covers manually. For PDFs, you can search text and check the document page by page. For videos, you can review detected faces or place a cover for a selected time range.

Detection can miss things. Manual video covers stay in a fixed position, so moving details need careful review.

There's no account requirement. The app has a free daily export allowance and an optional one-time upgrade, with no subscription.

Website: https://zeronet-redact.materialofair.chatgpt.site/en/
App Store: https://apps.apple.com/us/app/zeronet-redact-blur-censor/id6756290503

If you try it and find a confusing step, I'd appreciate a description using a dummy file rather than your private document.
```

## 3. Show HN 提交素材

仅在未重复提交同一产品、作者能参与讨论时使用。提交可直接试用的 App Store 链接，官网和源码放首评。不要把“做了一个网站”当作 Show HN 产品发布，也不要以普通版本更新重复提交。

Title:

```text
Show HN: ZeroNet Redact – On-device redaction for iPhone and iPad
```

URL:

```text
https://apps.apple.com/us/app/zeronet-redact-blur-censor/id6756290503
```

First comment:

```text
I'm the developer. ZeroNet Redact is a native iPhone/iPad app for removing private details from files before sharing them.

I wanted the editing workflow to keep originals on the device and make review an explicit step. It supports screenshots, PDFs and videos, with local processing and no account requirement. Source code is available below.

The important limitation is that detection can miss content. Users still need to inspect their exported files, especially when a detail moves in a video.

You can try the app with a free daily export allowance. There's an optional one-time purchase; purchases and restoration use Apple services.

Website: https://zeronet-redact.materialofair.chatgpt.site/en/
Source: https://github.com/materialofair/ZeroNet-Redact
```

## 4. Product Hunt 素材

第二阶段使用：先准备实际录屏、3 张 App 截图，并检查是否已有该产品条目或历史发布。已有发布应按重新发布规则评估，不创建重复条目。下面是可填入表单的短文案，不代表已完成发布排期。

Name: ZeroNet Redact

Tagline:

```text
Redact photos, PDFs and videos on your iPhone
```

Description:

```text
Prepare files for sharing with on-device redaction for iPhone and iPad. Review private details, add covers and check your export. No original uploads or account required. Free daily exports, with an optional one-time upgrade.
```

Maker comment:

```text
Hi, I'm the maker of ZeroNet Redact.

The app is built around a small task: choosing which parts of a file to share. Import a screenshot, PDF or video, review the areas to cover, then inspect the exported result.

Content processing stays on your device. Automatic detection is a starting point, and the review step matters because it can miss private details.

You can try the workflow without creating an account. A one-time upgrade extends the free export allowance; there is no subscription.

Thanks for trying it. Please use a dummy file if you share an example or report an issue.
```

截图顺序：截图文字复核 → PDF 遮挡后结果 → 视频时间区间遮挡。全部使用真实 App 截图和虚构内容。

## 5. 25 秒英文演示脚本

这是待录制分镜，不是已完成的视频。只展示实际操作，保留真实等待时间或明确标注剪辑。

| 时间 | 画面 | 英文字幕/旁白 |
|---|---|---|
| 0–3s | 虚构订单截图，显示 demo@example.com | Before you share this screenshot, check what goes with it. |
| 3–7s | 在 App 中导入截图 | Open it in ZeroNet Redact. |
| 7–13s | 查看检测结果，补选需要遮挡的区域 | Review the details you want to hide. |
| 13–19s | 应用实心遮挡，导出并打开结果 | Add covers, then inspect the exported copy. |
| 19–25s | 结果与 App 名称、网址 | Process on your iPhone. No original uploads. Try it free. |

结束画面小字：Detection can miss details. Review before sharing.

## 6. 七天执行顺序

| 阶段 | 动作 | 验证 |
|---|---|---|
| Day 1 | 修正下面的落地页入口问题；录制截图演示 | 官网按钮可到商店，录屏覆盖完整导出流程 |
| Day 2 | 用开发者 X 账号发布首发帖和演示 | 保存帖子 URL，24/72 小时记录可见数据 |
| Day 3 | 符合条件时提交 Show HN，并留出回复时间 | 记录真实试用问题，不索要投票 |
| Day 4 | 回复已有问题，更新 FAQ 草稿 | 每项反馈标明场景、是否复现 |
| Day 5 | 发布独立 PDF 演示/第二条 X 帖 | 演示导出文件中的文字选择行为 |
| 合资格周日 | 在 r/apple 发开发者自荐正文 | 先核对账号历史和最新社区规则 |
| Day 7 | 按可归因下载和有效反馈比较渠道 | 决定继续哪个渠道，是否准备 Product Hunt |

如果账号没有受众或不满足社区资格，时间表顺延；不购买互动、不群发私信。Product Hunt 暂不挤进第一周，以素材和可回复时间为准。

## 7. 网站与入口修正项

以下只是建议，未修改或部署线上网站。

1. 英文页 HTML 已有 title、description、canonical 和中英文 hreflang。补充 og:title、og:description、og:image、og:url 和 Twitter Card 元信息，让社交链接有清晰预览。分享图使用真实 App 截图；建议制作 1200×630 图。
2. 首页目前使用功能示意图。增加上述实际操作视频，帮助用户确认这是能下载使用的 App。
3. 页脚增加源码、隐私政策和反馈入口。已有 App Store 入口保留。
4. 本地 readme.md 的两处 App Store 下载链接仍是 # / Coming Soon；应换成实际下载 URL，并加入官网入口。这里只记录问题，尚未改 README。
5. App Store 的 Developer Website 当前指向 GitHub；可在 App Store Connect 改为英文官网。年龄分级字段显示 Advertising，与“无广告”宣传可能造成疑惑；先核对后台问卷和实际行为，当前推广稿不写“无广告”。
6. robots.txt、sitemap.xml 在本次请求返回 403，无法确认实际配置；不能据此断言搜索引擎被屏蔽。需另行通过站点后台或搜索引擎工具验证。

建议 OG 标题：ZeroNet Redact — Redact private details on your iPhone

建议 OG 描述：Prepare photos, PDFs and videos for sharing. Process on your device, review your export, and keep originals off the server.

## 8. 衡量方式

先记录各帖子原生曝光和点击；有 App Store Connect 权限后查看下载与可用来源数据。网站没有接入统计时，UTM 参数本身不会产生报表，不把帖子点击当作下载。渠道归因暂不可用时，记录总下载变化但不声称因果关系。

用同样的 24 小时与 72 小时窗口观察，区分浏览、点击、下载、实际反馈四层结果。不要为了推广在 App 中增加与隐私承诺冲突的追踪。

## 来源与验证范围

- [英文官网](https://zeronet-redact.materialofair.chatgpt.site/en/)：通过 curl 获取 HTML，检查内容、CTA 与元信息。
- [美国区 App Store](https://apps.apple.com/us/app/zeronet-redact-blur-censor/id6756290503)：核对版本、购买模式、平台支持和功能口径；未真机复测。
- 本地 PRODUCT.md、readme.md、CHANGELOG.md、PRIVACY_POLICY.md：定位与公开口径交叉检查，不用旧文档覆盖在线版本事实。
- [Show HN 指南](https://news.ycombinator.com/showhn.html)：可试用产品、作者参与讨论、不要索取投票。
- [r/apple 规则](https://www.reddit.com/r/apple/wiki/rules/)：周日自荐与参与资格；账号资格尚未检查。
- [Product Hunt 官方发布指南](https://www.producthunt.com/launch)及[推广规则](https://www.producthunt.com/launch/sharing-your-launch)：准备素材、回应讨论，不以奖励换投票。

后续实际发布需要确定账号与选用的稿件；没有任何内容已被公开发送。
