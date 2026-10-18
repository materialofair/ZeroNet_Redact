# PDF 场景推广执行包（历史方案，已取消 PDF 优先定位）

准备日期：2026-09-26。用户已纠正定位：照片、视频、文档脱敏并列；以下 PDF 优先实验仅作为历史记录，不再执行。最新状态：1.5.1（13）构建上传成功，商店文案和分级草稿已保存；真实英文 PDF 截图已制作，待上传和提交审核。早期阶段记录保留在下文，当前执行范围以 [1.5.1 发布记录](../1.5.1/README.md) 为准。本文不包含经营数据。

## 定位与边界

本轮只验证一个入口：在 iPhone 上查找 PDF 中重复出现的敏感文字，逐页检查、遮挡并导出分享。

目标是判断这一表达能否带来可持续的下载与付费改善。它是实验假设，不是已证实的需求或竞争优势。不要求用户访谈，不新增注册、埋点、广告 SDK 或私人文件上传。不改价格、免费额度或产品功能。

推广语气沿用 PRODUCT.md 和当前英文商店页：短句、具体操作、清楚说明限制，不承诺完整自动识别，不使用竞品贬低、虚构评价和用户量。

## 先执行的具体改动

1. 修正 README 中英文下载入口，添加官网与免费额度说明。验证：链接能打开对应 App，文案与 UsageTracker.swift 一致。
2. 登录 App Store Connect，确认 App ID 6756290503、当前线上版本和 English (U.S.)。保存当前推广文本，再仅替换为 promotion.json 的 first_change_only.promotionalText。验证：保存后重新打开仍显示新文案，记录生效时间，再检查公开商店页。
3. 将 Developer Website 对应的 Marketing URL 指向已经验证可访问的英文官网。先确认后台字段是否允许当前状态编辑；如需版本审核，留到下一次正常发版，不强行创建新版本。
4. 核对年龄分级问卷：当前公开页面列出 Advertising 和 Unrestricted Web Access。源码抽查未发现广告 SDK 或内置任意网页浏览器，但这不是完整二进制审计。应依据实际上线版本确认后填写，不为了降低分级猜测答案。

推广文本不需要提交新的 App 版本；其他字段依后台当前状态和 Apple 审核要求处理。本轮先维持名称、副标题、关键词、截图、长描述不变。第一阶段测试范围只是 PDF 场景的推广文本，不能把它解释成搜索关键词或截图实验。

### 可直接发布的英文推广文本

```text
Redact a PDF before you share it. Find repeated text, review each page and export a copy. Process on your device. Try 3 PDF exports a day free.
```

## 下一阶段截图分镜（尚未制作成图片）

仅当第一阶段完成、决定继续时制作一套；不同时上线多个变体。必须用真实 App 界面，不能把示意图当作实际功能截图。

| 顺序 | 英文标题 | 需要真实展示的画面 |
|---|---|---|
| 1 | Redact your PDF before sharing | 同一份虚构 PDF 的原文与实际导出结果；标明 Before / Exported copy |
| 2 | Find repeated private details | 搜索 demo@example.com，显示多个页面的实际匹配结果；不要暗示一次自动清除全文 |
| 3 | Check every page | 待处理页面导航、手动补选遮挡，体现人工复核 |
| 4 | Process on your device | 真实导出预览；说明 No original uploads，并标注 Review before sharing |
| 5 | Try 3 PDF exports a day free | 准确说明免费边界和可选一次性购买；不写全球统一价格 |

素材验收：3 页虚构文档，每页有相同的 demo@example.com 和不同的 PUBLIC-PAGE 标记。完整导入、搜索、遮挡、导出；在另一 PDF 阅读器检查遮挡区域文字不可选中/复制、公开文字仍可读、页数完整。搜索漏检或扫描件要手动复核。不要仅凭编辑器预览声称输出安全。

目前没有新拍摄的真实截图或录屏，也没有完成上述真机验收。现有单元测试文件不代表本次已运行通过。

## 已有站外渠道的备用材料

不新增密集发帖计划。只有已有渠道可操作且入口正确时，使用这一条英文 PDF 内容；记录实际发布 URL。不要将这份草稿计为发布。

```text
Before sharing a PDF from your iPhone, check what goes with it.

ZeroNet Redact lets you find repeated text, review each page and export a redacted copy. Processing stays on your device.

Try 3 PDF exports a day free:
https://apps.apple.com/app/id6756290503
```

YouTube 已有 PDF 视频的简短说明可改为：

```text
Find repeated private text, review every page, then export a redacted copy with ZeroNet Redact for iPhone and iPad. Content processing stays on your device. Review the full export before sharing. Download via the channel profile link.
```

最后一句只能在频道资料已配置且验证可点击的下载入口后使用。不要把 Shorts 描述里的纯文本 URL 当作已验证下载路径。

## 观察方案

- 基线：正式生效前完整 28 天；若仅能取得更短周期，前后都使用同长度。固定地区、设备平台、来源及指标定义。
- T0：以公开商店文案实际生效日期为准，排除当天；维护修正和推广文本变动分别记时间。
- T0 后第 14 天：仅检查数据是否可用、来源是否变化，不因几次下载改动实验。
- T0 后第 28 天：比较首次下载、独立付费用户、所得、退款和来源；原生转化率采用 Apple 指标，不用全部首次下载除以产品页查看冒充用户路径转化率。
- 准备投入建议上限 3 小时，后续每周最多 15 分钟看汇总数据；这是本轮工作预算建议，不是行业标准。没有安排自动定期任务。
- 没有来源或同群数据时记 unknown，不填零。活动链接直接在 App Store Connect 生成，不编造 pt 参数，不为个人创建编码，不加第三方追踪跳转。
- 营销活动数据受隐私门槛限制；缺少记录不证明没有下载。若没有活动链接，可先使用普通 App Store URL 与来源汇总。

### 决策规则

| 28 天后结果 | 下一步 |
|---|---|
| 同来源下载在两个相邻观察窗口均改善，且独立付费用户也增加 | 值得再重复一轮；不能宣称已有统计显著性或规模化能力 |
| 下载增加但独立付费没有改善 | 记录为获客线索；无法仅凭这点判断免费额度或定价问题 |
| 几次下载波动或数据持续不足 | 不宣布成功，转低维护；需要新的明确证据才扩大投入 |
| 发现可复现的导出/隐私缺陷 | 先修复并复测，再继续宣传相关能力 |

前后比较不是随机实验；季节、来源、版本更新都可能影响结果。没有自动续期或广告预算。

## 发布记录

| 项目 | 当前状态 | 完成证据 |
|---|---|---|
| README 入口与口径修正 | 本地完成，未推送 | git diff |
| 英文推广文本 | 已在后台保存 | Comet 中关闭编辑框后，字段显示新文案 |
| App Store Connect 修改 | 英文推广文本已保存；营销网址字段锁定 | 1.5.0 可分发，English (U.S.) |
| 年龄分级核对 | 已发现公开字段，待后台核实 | 公开商店页，源码抽查 |
| 新截图/演示 | 分镜完成，未制作 | 尚无真实图像或录屏 |
| 社交发布 | 未执行 | 尚无帖子 URL |
| 营销活动链接 | 未生成 | 使用普通下载 URL |

## 依据

- [当前美国区商店页](https://apps.apple.com/us/app/zeronet-redact-blur-censor/id6756290503)：2026-09-26 核对 1.5.0、免费额度、平台和购买方式。
- [英文官网](https://zeronet-redact.materialofair.chatgpt.site/en/)：同日 HTTP 200，下载链接正确。
- [Apple 产品页与推广文本](https://developer.apple.com/app-store/product-page/)：推广文本上限 170 字符，可不提交新版本更新。
- [Apple 指标定义](https://developer.apple.com/help/app-store-connect-analytics/reference/metrics-definitions)：区分首次下载、总下载、独立付费用户与交易数。
- [Apple 营销活动链接](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links)：后台生成，聚合指标和小样本门槛。
- [年龄分级定义](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)：依实际功能填写。
- 本地源码：UsageTracker.swift、StoreManager.swift、PDFReviewNavigator.swift；现有商店资料 docs/app-store/1.5/metadata.json。

## 2026-09-26 Comet 执行补记

复用用户已登录的现有标签页，保存英文推广文本并确认后台字段显示新内容。营销网址在已发布版本中禁用，保持原值；未创建新版本。当前英文截图为照片、视频、分享三张，PDF 独立截图待下一次正常发版补齐。公开页面实际生效时间尚未确定，因此尚未启动 28 天统计窗口。

## 1.5.1 执行进展

用户确认继续准备新版本后，范围扩展为 PDF 截图、英文长描述、官网入口和年龄分级修正。构建 1.5.1（13）已上传成功。问卷中的“不受限的网页访问”和“广告”由是改为否，Apple 计算为 4+，后台显示已编辑，随新版发布。签名环境下 PDF 相关 12 项测试通过；三页虚构 PDF 实际导出后，pypdf 验证邮箱不可提取、公开文字和页数保留。真实截图在 ../1.5.1/screenshots/en-US/。截图上传及送审尚未完成。
