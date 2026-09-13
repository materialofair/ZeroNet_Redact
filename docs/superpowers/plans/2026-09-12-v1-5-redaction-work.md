# ZeroNet Redact v1.5.0 Implementation Plan

## 2026-09-13 实施状态（优先于下方原始设计草案）

当前实现位于 `feat/v1.5-work`。这是开发版本，尚未发布；版本号暂保留 1.4.1。

| 工作项 | 实施状态 | 验收边界 |
|---|---|---|
| 1. 加密草稿 | 已接入图片、PDF、视频编辑器 | 图片旋转底图、遮挡、待处理文字、人脸选择、PDF 页码和视频设置/分析时间线；500ms 防抖及离开时保存。需真机强杀恢复复核 |
| 2. 重复文字搜索 | 已接入编辑器搜索入口 | 图片 OCR、PDF 跨词短语、重复命中、全选/当前页、定位和保留待处理；跨页 PDF 应用支持一次撤销 |
| 3. PDF 待处理导航 | 已接入 | 有待处理项的页面缩略图、计数、当前页提示、下一处循环定位 |
| 4. 系统分享扩展 | 代码与嵌入目标已接入 | 图片/PDF、10 个附件、每个 15 MB 上限、独立加密收件箱、认证后导入、失败保留与重试；需配置签名并完成真机端到端验证 |
| 5. 导出处理记录 | 已接入 | 图片/PDF 输出格式、字节数、当前遮挡记录数及实际缺失的指定元数据字段；视频核验音轨数。不表示检测了全部隐私内容 |
| 6. 视频手动补漏 | 可选项，未实施 | 保留在后续独立工作中 |
| 7. 图片批处理队列 | 可选项，未实施 | 保留在后续独立工作中；幂等键必须同时包含原文件和处理规则版本 |
| 8. 发布验证 | 进行中 | 单元测试及模拟器构建记录见下述交付说明；真机、VoiceOver、大字体、分享来源矩阵尚待验证 |

技术修正：草稿采用 `BusinessLogic/Storage/EditorDraftStore.swift` 加密 sidecar，无需 Core Data 模型迁移。图片旋转后的替换底图仅以加密载荷保存。分享扩展使用独立 Keychain 密钥，不共享主库主密钥；扩展完成后提示用户打开主应用，不尝试绕过 iOS 限制唤起主应用。原计划中的实体名称、伪代码及尚未勾选的步骤保留作设计参考，不代表实际代码位置。

开发与发布检查：[v1.5 开发交付说明](../../v1.5-development-notes.md)。

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 在保持完全离线处理的前提下，让用户能恢复未完成编辑、批量处理重复敏感内容、快速复核多页文档，并从系统分享菜单直接进入脱敏流程。

**Architecture:** 继续使用 SwiftUI 编辑器、Core Data 文件记录和本地加密存储。草稿只保存可恢复的编辑状态，不保存明文原始文件；识别结果通过统一候选模型供图片和 PDF 复核。分享扩展只负责接收本地文件并交给主应用，耗时处理仍在主应用中完成。视频手动补漏使用时间区间与归一化矩形，不改变现有自动检测和导出管线。

**Tech Stack:** Swift 5、SwiftUI、Core Data、PDFKit、Vision、AVFoundation、MuPDF、XCTest、iOS 17.6+。

---

## 版本基线与范围

当前项目版本为 `1.4.1`，构建号为 `11`。本计划假定下一版为 `1.5.0`。提交 `0cd9c3e` 已完成导出后继续编辑，以及导出前未处理识别项复核与定位。

### v1.5.0 必须完成

1. 加密编辑草稿与恢复入口。
2. OCR 重复内容搜索和批量应用。
3. PDF 逐页待处理导航。
4. 图片/PDF 系统分享扩展。
5. 导出安全摘要。

### v1.5.0 可选完成

6. 视频时间线手动补漏。
7. 多图片批处理队列。

如果可选项无法在发布窗口内完成，不影响前 5 项发布；它们必须保持独立提交。

### v1.6.0 延后范围

人物级视频轨迹管理、更多贴纸样式、动画效果、云端识别和社交分享不纳入本版本。

## 文件与责任边界

| 文件或目录 | 责任 |
|---|---|
| `zeroNetRedact/zeroNetRedact/Models/CoreData/ZeroNetRedact.xcdatamodeld/ZeroNetRedact.xcdatamodel/contents` | 草稿实体及原文件关联 |
| `zeroNetRedact/zeroNetRedact/BusinessLogic/Storage/StorageManager.swift` | 草稿加密文件保存、读取、删除和清理 |
| `zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift` | 编辑状态快照、恢复、导出报告和草稿生命周期 |
| `zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift` | 草稿恢复、搜索入口、导出摘要 |
| `zeroNetRedact/zeroNetRedact/Views/BrushEditor/` | 复核列表、逐页导航、搜索结果和导出摘要 |
| `zeroNetRedact/zeroNetRedact/BusinessLogic/Recognition/TextRecognizer.swift` | 统一文本查找和重复匹配结果 |
| `zeroNetRedact/zeroNetRedact/Views/Video/` | 视频时间线和手动补漏 |
| `zeroNetRedact/ShareExtension/` | 图片/PDF 分享扩展 |
| `zeroNetRedact/zeroNetRedactTests/` | 单元和状态恢复测试 |
| `CHANGELOG.md`、`readme.md`、`PRIVACY_POLICY.md` | 版本行为与隐私说明同步 |

## Task 1: 加密编辑草稿和恢复入口

**目标：** 系统终止应用、主动离开编辑器或切换文件后，用户可以继续上次编辑；草稿中不能出现原始图片、PDF 或视频明文数据。

**Files:**

- Modify: `zeroNetRedact/zeroNetRedact/Models/CoreData/ZeroNetRedact.xcdatamodeld/ZeroNetRedact.xcdatamodel/contents`
- Create: `zeroNetRedact/zeroNetRedact/Models/CoreData/RedactionDraft+CoreDataClass.swift`
- Create: `zeroNetRedact/zeroNetRedact/Models/CoreData/RedactionDraft+CoreDataProperties.swift`
- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Editor/RedactionDraftPayload.swift`
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Storage/StorageManager.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift`
- Create: `zeroNetRedact/zeroNetRedact/Views/Editor/DraftRecoveryBanner.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/RedactionDraftTests.swift`

- [ ] **Step 1: 定义可编码的草稿载荷**

```swift
struct RedactionDraftPayload: Codable, Equatable {
    var schemaVersion: Int = 1
    var currentPDFPageIndex: Int
    var selectedEffectRawValue: String
    var regions: [RedactionDraftRegion]
    var pendingDetections: [RedactionDraftRegion]
    var videoIntervals: [RedactionDraftVideoInterval]
}

struct RedactionDraftRegion: Codable, Equatable {
    var pageIndex: Int?
    var normalizedRect: CGRectCodable
    var effectRawValue: String
}

struct RedactionDraftVideoInterval: Codable, Equatable {
    var startSeconds: Double
    var endSeconds: Double
    var normalizedRect: CGRectCodable
    var effectRawValue: String
}

struct CGRectCodable: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
```

区域使用归一化坐标；保存时转换图片像素坐标和 PDF 页面坐标，恢复时再转换回渲染尺寸。

- [ ] **Step 2: 先写编码、加密存取和删除测试**

覆盖相同载荷编码后可解码、草稿文件经过 `CryptoEngine` 加密、读取不存在的草稿返回 `nil`、删除后磁盘没有文件、不同原文件 ID 互不覆盖。

Run:

```bash
xcodebuild -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:zeroNetRedactTests/RedactionDraftTests test CODE_SIGNING_ALLOWED=NO
```

Expected: 实现前测试失败，完成存取后全部通过。

- [ ] **Step 3: 增加 Core Data 草稿实体和存储 API**

提供以下接口：

```swift
func saveDraft(_ payload: RedactionDraftPayload, for file: RedactableFile) throws
func loadDraft(for file: RedactableFile) throws -> RedactionDraftPayload?
func deleteDraft(for file: RedactableFile) throws
func deleteDrafts(forOriginalFileID id: UUID) throws
```

删除原文件的路径必须调用 `deleteDrafts(forOriginalFileID:)`，避免留下关联草稿。

- [ ] **Step 4: 节流保存并在加载时恢复**

`EditorViewModel` 在应用、移动、缩放、删除遮挡、检测完成、PDF 翻页和视频设置改变后以 500ms 节流保存。`loadFile()` 完成后读取草稿并显示恢复横幅，提供“继续编辑”和“删除草稿”。

- [ ] **Step 5: 验证恢复和清理**

测试恢复到第二页 PDF、恢复待处理候选、删除原文件后清理草稿、导出完成前保留草稿、点击“完成”后删除草稿。

- [ ] **Step 6: 提交**

```bash
git add zeroNetRedact/zeroNetRedact/Models/CoreData \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Editor/RedactionDraftPayload.swift \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Storage/StorageManager.swift \
  zeroNetRedact/zeroNetRedact/Views/Editor zeroNetRedact/zeroNetRedactTests/RedactionDraftTests.swift
git commit -m "feat: persist encrypted redaction drafts"
```

## Task 2: OCR 重复内容搜索和批量应用

**目标：** 用户输入姓名、公司名或任意文本后，查看所有匹配位置，选择后一次应用同一种遮挡效果。

**Files:**

- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Recognition/TextRecognizer.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Utils/SensitivePatterns.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Models/Protocols/TextRecognition.swift`
- Create: `zeroNetRedact/zeroNetRedact/Views/BrushEditor/SensitiveTextSearchView.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/TextSearchTests.swift`

- [ ] **Step 1: 先写跨页和重复文本测试**

测试同一姓名在第 1、3、5 页出现、大小写和首尾空格、空查询、无匹配查询。结果保留页面索引和每次边界框；不同页面相同坐标不能去重。

- [ ] **Step 2: 定义搜索接口**

```swift
func findOccurrences(
    of query: String,
    in texts: [RecognizedText],
    options: TextSearchOptions = .default
) -> [SensitiveRegion]
```

默认忽略首尾空格，拒绝少于 1 个有效字符的查询，结果沿用 `SensitiveRegion`。

- [ ] **Step 3: 添加搜索面板**

显示“找到 N 处，分布在 M 页”；点击结果定位；支持全选当前页、全选所有结果、应用所选和忽略所选。批量应用生成一个撤销快照。

- [ ] **Step 4: 验证**

```bash
xcodebuild -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:zeroNetRedactTests/TextSearchTests \
  -only-testing:zeroNetRedactTests/PageIndexDedupTests test CODE_SIGNING_ALLOWED=NO
```

Expected: 搜索和去重测试通过；一次撤销可以还原整批区域；未应用结果仍进入导出前复核清单。

- [ ] **Step 5: 提交**

```bash
git add zeroNetRedact/zeroNetRedact/BusinessLogic/Recognition \
  zeroNetRedact/zeroNetRedact/Utils/SensitivePatterns.swift \
  zeroNetRedact/zeroNetRedact/Models/Protocols/TextRecognition.swift \
  zeroNetRedact/zeroNetRedact/Views/BrushEditor zeroNetRedact/zeroNetRedactTests/TextSearchTests.swift
git commit -m "feat: search and redact repeated text"
```

## Task 3: PDF 逐页待处理导航

**目标：** 用户能从文档概览看到每页待处理数量，并在“下一处待复核”和页面之间快速跳转。

**Files:**

- Create: `zeroNetRedact/zeroNetRedact/Views/BrushEditor/PDFReviewNavigator.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/PDFReviewNavigatorTests.swift`

- [ ] **Step 1: 定义页面摘要状态**

提供 `[(pageIndex: Int, pendingCount: Int)]`；按页升序排列；无候选页不显示；未知页码单独显示，不能静默丢弃。

- [ ] **Step 2: 先写导航状态测试**

覆盖当前页处理后跳到下一页、候选全部处理后隐藏导航、删除候选后数量同步减少、同一页多个候选按原顺序定位。

- [ ] **Step 3: 实现缩略图和下一处按钮**

缩略图显示页码和数量；“下一处”从当前页之后开始并循环；跳转后清除旧页选择并闪烁目标区域，复用现有 PDF 渲染和翻页逻辑。

- [ ] **Step 4: 手动验收多页 PDF**

准备至少 5 页、候选位于第 1、3、5 页的 PDF，确认应用本页不会误报整份文档完成，导出前仍能看到剩余页。

- [ ] **Step 5: 提交**

```bash
git add zeroNetRedact/zeroNetRedact/Views/BrushEditor/PDFReviewNavigator.swift \
  zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift \
  zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift \
  zeroNetRedact/zeroNetRedactTests/PDFReviewNavigatorTests.swift
git commit -m "feat: navigate pending PDF redactions"
```

## Task 4: 图片和 PDF 系统分享扩展

**目标：** 用户在 Photos 或 Files 中选择图片/PDF 后，通过系统分享菜单直接进入 ZeroNet Redact。

**Files:**

- Create: `zeroNetRedact/ShareExtension/ShareViewController.swift`
- Create: `zeroNetRedact/ShareExtension/ShareImportCoordinator.swift`
- Create: `zeroNetRedact/ShareExtension/Info.plist`
- Create: `zeroNetRedact/ShareExtension/ShareExtension.entitlements`
- Modify: `zeroNetRedact/zeroNetRedact/zeroNetRedact.entitlements`
- Modify: `zeroNetRedact/zeroNetRedact.xcodeproj/project.pbxproj`
- Test: `zeroNetRedact/zeroNetRedactTests/ShareImportCoordinatorTests.swift`

- [ ] **Step 1: 定义接收类型和生命周期测试**

只接受 `public.image`、`com.adobe.pdf` 和系统文件 URL；拒绝视频、未知类型和超过大小上限的输入，并给出可读错误。多个附件按选择顺序处理。

- [ ] **Step 2: 实现共享容器的临时加密交接**

扩展将附件复制到 App Group `group.zeronet.redact` 的临时目录后立即加密，向主应用发送临时文件 ID；主应用导入完成或失败后删除共享容器临时数据。共享容器不能留下明文原始文件。

- [ ] **Step 3: 添加主应用导入路由**

主应用启动或回到前台时读取待处理 ID，导入现有 `ImportManager`，自动打开编辑器；多个文件进入导入结果页，不自动并行打开多个编辑器。

- [ ] **Step 4: 真机和模拟器验收**

验证 Photos 图片、Files PDF、取消扩展、主应用未运行、主应用已锁定、导入失败和临时文件清理。长耗时检测必须回到主应用。

- [ ] **Step 5: 提交**

```bash
git add zeroNetRedact/ShareExtension \
  zeroNetRedact/zeroNetRedact/zeroNetRedact.entitlements \
  zeroNetRedact/zeroNetRedact.xcodeproj/project.pbxproj \
  zeroNetRedact/zeroNetRedactTests/ShareImportCoordinatorTests.swift
git commit -m "feat: add local photo and PDF share import"
```

## Task 5: 导出安全摘要

**目标：** 导出完成后说明处理区域数量、文件类型、音频方式和实际清理的元数据，让用户知道副本做了什么。

**Files:**

- Create: `zeroNetRedact/zeroNetRedact/Models/ExportReport.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/BrushEditor/EditorExportCompletionView.swift`
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Editor/PDFRedactionEditor.swift`
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoMuxer.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/ExportReportTests.swift`

- [ ] **Step 1: 定义导出报告**

```swift
struct ExportReport: Equatable {
    let fileType: FileType
    let appliedRegionCount: Int
    let removedMetadataFields: [String]
    let audioMode: AudioExportMode?
    let warnings: [String]
}

enum AudioExportMode: String, Codable {
    case original
    case muted
    case voicePreset
}
```

报告只描述实际完成的操作，不能显示检测无法证明的“已全部保护”。

- [ ] **Step 2: 从各导出器收集真实结果**

PDF 报告来自实际移除区域和 `sanitizeMetadata`；视频报告来自最终音频轨道和元数据数组；图片报告来自实际应用的遮挡区域。失败时不创建成功报告。

- [ ] **Step 3: 更新完成面板**

完成面板显示摘要、警告和再次分享按钮；取消系统分享只关闭系统面板，不清除报告或编辑状态。

- [ ] **Step 4: 测试报告准确性**

覆盖 PDF 有/无元数据、视觉兜底警告、视频保留音频和静音导出；报告字段与导出数据不一致时测试必须失败。

- [ ] **Step 5: 提交**

```bash
git add zeroNetRedact/zeroNetRedact/Models/ExportReport.swift \
  zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift \
  zeroNetRedact/zeroNetRedact/Views/BrushEditor/EditorExportCompletionView.swift \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Editor/PDFRedactionEditor.swift \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoMuxer.swift \
  zeroNetRedact/zeroNetRedactTests/ExportReportTests.swift
git commit -m "feat: show export safety summary"
```

## Task 6: 视频时间线手动补漏（可选）

**目标：** 自动人脸检测遗漏或跟踪中断时，用户可以在指定时间段手动添加遮挡，并在导出前检查结果。

**Files:**

- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoManualRedaction.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Video/VideoEditorViewModel.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Video/VideoEditorView.swift`
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoExporter.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/VideoManualRedactionTests.swift`

- [ ] **Step 1: 定义时间区间和归一化矩形**

```swift
struct ManualVideoRedaction: Identifiable, Equatable, Codable {
    let id: UUID
    var startSeconds: Double
    var endSeconds: Double
    var normalizedRect: CGRectCodable
    var effectRawValue: String
}
```

创建时保证 `0 <= startSeconds < endSeconds <= duration`；越界区间和不在 0...1 范围内的矩形必须拒绝。

- [ ] **Step 2: 先写时间范围和导出覆盖测试**

覆盖区间边界、相邻区间、播放头移动后区域显示、手动区域与自动轨迹同时存在，以及取消导出后不保存临时区域。

- [ ] **Step 3: 添加时间线和手动画框交互**

时间线显示自动检测段和手动覆盖段；拖动播放头定位，点击“添加遮挡”进入画框模式，再选择结束时间。默认不扩大用户指定的时间范围。

- [ ] **Step 4: 接入导出器并验收短视频**

使用 5 秒、10fps 测试视频，验证区域只在指定区间出现，首尾帧、音频模式和取消操作不回归。

- [ ] **Step 5: 提交**

```bash
git add zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoManualRedaction.swift \
  zeroNetRedact/zeroNetRedact/Views/Video \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoExporter.swift \
  zeroNetRedact/zeroNetRedactTests/VideoManualRedactionTests.swift
git commit -m "feat: allow manual video redaction intervals"
```

## Task 7: 多图片批处理队列（可选）

**目标：** 对一组图片复用同一套遮挡规则，逐张保留复核和失败重试状态。

**Files:**

- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Batch/BatchRedactionQueue.swift`
- Create: `zeroNetRedact/zeroNetRedact/Models/BatchRedactionItem.swift`
- Create: `zeroNetRedact/zeroNetRedact/Views/Batch/BatchRedactionView.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Import/ImportViewModel.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/BatchRedactionQueueTests.swift`

- [ ] **Step 1: 定义队列状态和幂等键**

每项包含原文件 ID、内容哈希、状态（等待、处理中、成功、失败、需复核）和错误信息。成功项再次运行时依据内容哈希跳过，不能重复生成副本。

- [ ] **Step 2: 写状态迁移测试**

覆盖成功、失败重试、取消、单项失败不影响其他项、应用终止后恢复等待项和重复内容跳过。

- [ ] **Step 3: 实现有限并发和结果复核**

默认一次处理一个文件，避免同时解码多张大图造成内存峰值；每项完成后保存结果并允许单独打开编辑器复核。

- [ ] **Step 4: 手动验证 20 张图片队列**

验证进度、取消、失败重试、成功项不重复导出和原件加密存储不变。

- [ ] **Step 5: 提交**

```bash
git add zeroNetRedact/zeroNetRedact/BusinessLogic/Batch \
  zeroNetRedact/zeroNetRedact/Models/BatchRedactionItem.swift \
  zeroNetRedact/zeroNetRedact/Views/Batch \
  zeroNetRedact/zeroNetRedact/Views/Import/ImportViewModel.swift \
  zeroNetRedact/zeroNetRedactTests/BatchRedactionQueueTests.swift
git commit -m "feat: add resumable image redaction queue"
```

## Task 8: 发布前验证和文档同步

**Files:**

- Modify: `zeroNetRedact/zeroNetRedact.xcodeproj/project.pbxproj`
- Modify: `CHANGELOG.md`
- Modify: `readme.md`
- Modify: `PRIVACY_POLICY.md`（仅在分享扩展或数据流描述变化时更新）
- Test: `zeroNetRedact/zeroNetRedactTests/`
- Test: `zeroNetRedact/zeroNetRedactUITests/`

- [ ] **Step 1: 更新版本号**

将 `MARKETING_VERSION` 从 `1.4.1` 更新为 `1.5.0`；构建号通过现有 Release 脚本递增，不手动覆盖脚本生成的值。

- [ ] **Step 2: 运行完整测试和编译检查**

```bash
xcodebuild -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact \\
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \\
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO

xcodebuild -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact \\
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Expected: 测试 0 failures，构建结果为 `BUILD SUCCEEDED`。

- [ ] **Step 3: 运行手动验收矩阵**

| 场景 | 期望结果 |
|---|---|
| 图片识别、处理、导出、取消分享 | 取消分享后仍留在编辑流程 |
| 多页 PDF 候选分布在不同页 | 页面数量、定位和剩余候选准确 |
| 应用被系统终止后重开 | 草稿可恢复，原始文件仍加密 |
| Photos 分享图片 | 主应用自动进入待编辑文件 |
| Files 分享 PDF | PDF 页面和候选识别正常 |
| 视频快速移动人脸 | 可用手动时间区间补漏 |
| 导出失败或取消 | 不产生成功记录、孤儿明文文件或错误计数 |
| 明暗模式、动态字体、VoiceOver、减少动态效果 | 主要操作仍可完成，按钮触达区域至少 44pt |

- [ ] **Step 4: 更新版本文档**

`CHANGELOG.md` 记录新增能力和已知限制；`readme.md` 明确说明自动检测需要人工复核、视频分析可能降采样，以及分享扩展仍保持本地处理；隐私政策只描述实际实现的数据流。

- [ ] **Step 5: 发布前提交和推送**

```bash
git diff --check
git status --short
git log -1 --oneline
git push origin main
```

Expected: 发布提交只包含 v1.5.0 相关文件，远程 `main` 与本地提交一致。

## 完成定义

- 必须完成的 5 项功能均有单元测试、至少一条 UI 手动验收路径和中英文文案。
- 草稿、分享扩展和批处理流程中没有明文原始文件残留。
- 导出前保留“待处理 / 已忽略”的明确状态，不显示无法证明的绝对安全结论。
- PDF 真删除、视频音频处理、图片撤销重做和现有免费额度逻辑没有回归。
- 全量测试通过，模拟器构建通过，至少在一台真实 iPhone 或 iPad 上完成导入、编辑和导出验收。
- `CHANGELOG.md`、`readme.md` 和隐私政策与实际版本行为一致。

## 版本评估指标

不新增联网埋点，使用本地测试记录评估：

1. 从导入到第一次成功导出的步骤数。
2. 多页 PDF 找到下一处待处理项所需的点击数。
3. 同一文本出现 10 次时的处理操作数。
4. 应用终止后恢复草稿的成功率。
5. 导出后取消分享并继续编辑的成功率。
6. 视频检测漏检样例中，手动补漏后正确覆盖的时间区间比例。

## 依赖顺序

```text
草稿模型与存储
        ├── PDF 待处理导航
        ├── OCR 重复内容搜索
        └── 视频手动补漏

导出安全摘要 ──依赖── 各媒体导出器报告

系统分享扩展 ──依赖── 现有 ImportManager 与加密存储

批处理队列 ──依赖── 草稿、导出报告和现有多选导入
```

建议执行顺序为 `Task 1 → Task 2/3 → Task 5 → Task 4 → Task 6/7`。每个任务单独提交，出现回归时可以只回退对应功能。
