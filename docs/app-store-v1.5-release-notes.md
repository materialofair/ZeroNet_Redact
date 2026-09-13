# App Store 1.5 更新说明

2026-09-13：1.5.0（构建 12）已提交，最后核验状态为“正在等待审核”。中英文最终名称、副标题、关键词、推广文本和描述见 [metadata.json](app-store/1.5/metadata.json)。以下增长建议保留为最初讨论记录，实际字段以该 JSON 为准。

## 简体中文（可粘贴到“此版本的新功能”）

1.5 版本，让分享前的隐私处理更顺手。

• 全新页面布局：文件、脱敏文件和设置页面更加简洁，分组与筛选随手可达，留出更多空间查看文件。
• 更简单的视频遮挡：添加遮挡框，轻点定位、拖动调整大小，并选择生效时段。
• 编辑草稿：图片、PDF 和视频支持保存加密草稿，稍后继续处理。
• 文字处理更高效：搜索重复出现的文字，滑选需要隐藏的内容；PDF 支持快速定位待处理页面。
• 图片批处理：统一识别规则，逐张复核后导出，支持暂停和失败重试。
• 导出与分享更清晰：新增处理记录，优化成品预览与分享入口。

内容处理继续在设备本地完成，无需上传原文件。自动识别可能遗漏，请在分享前复核。

## English

Version 1.5 makes it easier to protect private information before sharing.

• A cleaner layout for Files, Redacted Files, and Settings, with compact group and filter menus.
• Easier manual video covers: add a box, tap to position it, drag to resize, and choose when it appears.
• Encrypted editing drafts for photos, PDFs, and videos, so you can continue later.
• Find repeated text, swipe to select words, and quickly navigate PDF pages that need review.
• Prepare multiple images with shared detection rules, then review and export each one. Pause or retry as needed.
• Clearer export records and easier access to sharing from file previews.

Content processing stays on your device, without uploading your originals. Automatic detection can miss details; review your files before sharing.

## 提交备注（不要粘贴到商店更新日志）

- 手动视频框为固定位置，不宣传为自动跟随任意对象。
- 分享扩展需完成 App Group 签名和真机导入验收，因此未放入上面的主文案。验收后可增加：“可从系统分享菜单将图片和 PDF 导入应用，继续脱敏处理。”
- 已提交审核，尚不表示 1.5 已通过审核或正式发布。

## 首轮增长工作建议

1. 从 App Store Connect 导出近 28 天按地区及来源拆分的展示、产品页查看、首次下载和购买数据，区分发现问题与转化问题。不要将不同来源的总数直接相除，当成同一条用户路径。
2. 为中文市场测试更直观的名称“ZeroNet Redact：图片视频打码”，副标题“截图隐私遮挡，PDF 敏感文字脱敏”。它们是候选文案，尚无搜索量或转化数据验证。
3. 前三张截图依次展示：分享截图前隐藏个人信息、PDF 敏感文字处理、视频添加遮挡。每张只讲一个结果，使用虚构样例和真实界面；本地处理作为贯穿卖点。
4. README 当前中英文 App Store 链接仍为占位符，应补成真实商店链接；检查支持页面和应用介绍是否同步最新版本。
5. 用短演示验证需求：聊天截图隐私、合同 PDF、视频固定区域遮挡，各做两条真实操作演示。优先在一个目标市场测试，记录各内容带来的下载，而不是只看播放量。
6. 流量足够时使用 Product Page Optimization 测试首图；面向不同场景的外部流量可用自定产品页面。低流量时不要因少量样本宣布胜出，也不建议先大规模买量。
7. 当前美区公开页面的“广告”年龄分级标签与描述“无广告”不一致；按实际功能核对 App Store Connect 问卷。视频逐帧检测及免费额度描述也应与 1.5 实现一致。美区评价数量不代表全球评价或下载量。

来源（2026-09-13 查阅）：

- 当前美区商店：https://apps.apple.com/us/app/zeronet-redact/id6756290503
- Apple 产品页指导：https://developer.apple.com/app-store/product-page/
- 产品页优化：https://developer.apple.com/help/app-store-connect-analytics/acquisition/product-page-optimization
- 自定产品页面：https://developer.apple.com/app-store/custom-product-pages/
