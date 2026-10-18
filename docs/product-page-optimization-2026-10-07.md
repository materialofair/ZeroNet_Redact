# Redact 产品页优化记录 — 2026-10-07

## 本轮范围与状态

- App：zeroNet Redact: Blur & Censor，6756290503。
- Comet / App Store Connect 实时核实：1.5.1 可分发；1.5.2 正在等待审核。本次复制已上线 1.5.1 的素材创建独立自定产品页。
- 自定页：`PDF Sharing - Review and Redact - EN ZH - 20261007`。
- [后台自定页](https://appstoreconnect.apple.com/apps/6756290503/distribution/productpages/88998fa4-c803-469f-8e38-f515d94c4581)。
- 产品页面 ID：`f5adc965-24a2-4a31-9723-fc0446e66d3f`。
- 中英文文案、关键词关联、截图顺序已保存。用户于本轮回复“同意”后正式提交审核；后台显示“已提交 1 个项目”，自定页状态为“等待审核”。尚未验证公开可用。
- 默认产品页 1.5.1 的中文推广文本已更新保存；英文核对与已批准文案一致，保留原文。没有启动广告或产品页 A/B 测试。

## 定位与文案

场景：分享合同、收据或其他 PDF 前，找到敏感信息、逐页检查、遮盖后导出副本。沿用真实功能与演示数据，不承诺自动处理全部敏感信息。

### 自定页英文 — 152 字符

Sharing a PDF? Find sensitive text, review each page and export a redacted copy on your device. No account needed. Check the full result before sharing.

关联现有已上线关键词：`document`、`text`、`receipt`。

### 自定页简体中文 — 71 字符

分享合同、收据或 PDF 前，先查找并遮盖姓名、电话、邮箱等敏感信息。逐页检查后导出副本，内容在本机处理，无需注册账号。发送前请检查完整结果。

关联现有已上线关键词：`涂黑`、`邮箱`、`合同`。

## 截图

英文 iPhone 6.9 英寸来源截图顺序：

1. `Simulator Screenshot - iPhone 17 Pro Max - 2026-09-26 at 21.41.15.png`：PDF 编辑遮盖。
2. `Simulator Screenshot - iPhone 17 Pro Max - 2026-09-26 at 21.41.37.png`：PDF 文本查找。
3. `Simulator Screenshot - iPhone 17 Pro Max - 2026-09-26 at 21.42.23.png`：PDF 导出报告。
4. `01-photo-en.png`。
5. `02-video-en.png`。
6. `03-share-en.png`。

主界面 iPhone 6.3 英寸继承此来源素材，已复查排序。

简体中文 iPhone 6.9 英寸上传以下原生截图，均为 1320 × 2868，iPhone 6.3 英寸继承：

1. `docs/app-store/1.5.1/screenshots/zh-Hans/01-pdf.png`：中文查找敏感文本界面。
2. `docs/app-store/1.5.1/screenshots/zh-Hans/02-pdf.png`：中文编辑界面中已遮盖演示邮箱。

两张图的 PDF 示例正文为英文虚构资料。iPad 13 英寸仍沿用复制的三张原有截图，中文也继承这些素材；未制作完整中文 iPad PDF 流程图。本轮没有新增标题或搜索结果专用素材，也没有配置未经核实的深层链接。

## 默认页推广文本 — 已确认并保存

默认页继续覆盖照片、视频和 PDF 的完整用途，避免只覆盖自定页的 PDF 场景。

英文（163 字符，保留当前已上线英文文本）：

Redact photos, videos and PDFs on your device. Cover private details, review the result and share a copy. No account required. Try free; upgrade with one purchase.

简体中文（75 字符，已更新）：

分享照片、视频或 PDF 前，先遮盖不想公开的信息。在本机处理、预览并导出副本，无需注册账号。可免费体验，一次购买升级，无订阅。发送前请检查完整结果。

## 基线与效果验证

App Store Connect 90 天范围：2026-07-09 至 2026-10-06，UTC。调整前记录：3,160 次展示、147 次产品页查看、37 次首次下载，后台显示日平均转化率 1.65%。日平均转化率不是用上述总数自行相除所得。

审核通过并确认链接可访问后，再用专用链接进行 PDF 场景推广；按相同时间范围和流量来源观察自定页查看、首次下载及转化。当前数据不是本次调整带来的增长。样本较少，本轮暂不启动 A/B 测试。

## 验证与限制

- Comet 重新打开草稿，检查两种语言的推广文案、关键词选中值、保存按钮禁用状态，以及中文截图列表。
- Python 标准库检查全部提案字符数不超过 170；读取 PNG 文件头核实尺寸；人工查看两张中文 PDF 截图。
- 新增此记录；没有改动应用代码、现有原始截图、版本或在审提交。
- 后续优先补充中文 iPad PDF 演示素材。独立网页落地页不在当前默认范围内。

## 审核提交凭据

- [App 审核提交记录](https://appstoreconnect.apple.com/apps/6756290503/distribution/reviewsubmissions/details/0c9f395c-f286-4ac4-8902-f753e8e04d81)。
- 后台明确显示已提交 1 个项目；不能把“等待审核”作为公开可用或实际增长的证明。
- 默认产品页保存后重新加载或重新打开，并切换英语与简体中文，复查文案持久保存；尚未单独核实 App Store 客户端缓存刷新。
- 本轮本地验证：两仓库 `git diff --check` 均通过，Python 检查提交记录与文件空白格式通过。
