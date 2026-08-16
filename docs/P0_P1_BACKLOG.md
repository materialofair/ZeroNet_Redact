# P0 / P1 待办清单

> 状态：P0 与 P1 已全部清零（2026-08-16 一次性收尾）。
> 本清单保留各项的实现要点供回溯。`✅` 为已完成。

## P0

### ✅ P0-10 编辑器渲染性能

**问题**：每一笔涂抹、每一个检测区域应用，都会从当前图片**整图重新合成一次**，且全部在主线程执行。

- 位置：`Views/SimpleBrushEditor.swift` `applyMosaic()`（逐 stroke 循环调用）、`BusinessLogic/Editor/ImageRedactionEditor.swift` `applyRedaction` → `compositeImage`（整图 `UIGraphicsImageRenderer`）。
- 大图（12MP 相机照片）上连续应用 10+ 区域会卡顿数秒、内存峰值高。

**注意事项**：
1. 快照式撤销（`render(operations:)`）目前从原图**重放全部操作**，每次 undo 也是 O(n) 次全图合成——批量渲染改造要一并覆盖这条路径，否则历史长时撤销会卡。
2. PDF 页渲染存在同类问题：`EditorViewModel.renderCurrentPDFPage()` 注释声称 2x，实际是 2×屏幕倍率（3x 设备上 6x），大 PDF 内存压力大。
3. 渲染移后台时注意 `UIImage` 跨线程传递（用 CGImage/Data 传递更安全），以及 `@MainActor` 默认隔离下的状态回写。

**建议方向**：笔划合并为单次渲染；渲染移后台线程；只重画脏区；补回归测试（含撤销路径）。

## P1

### ✅ P1-1 列表筛选 / 排序

- `filterType` 是死代码：`ImportViewModel:33,97-98` 与 `AlbumViewModel:8,58-59` 定义了过滤谓词但没有任何 UI 绑定；无 `.searchable`；排序硬编码 `createdAt`/`exportedAt` 降序。
- 注意：要么接线 UI（全部/图片/PDF/视频），要么删掉死管道；搜索在已加载的内存数组上做即可，无需重建 fetch。

### ✅ P1-2 图片 / PDF 导出体验

- 导出只有按钮转圈：无进度、无取消（同步渲染，`Task.isCancelled` 检查打断不了）；文件 UUID 命名；无导出后分享 sheet；整 App 无"保存到系统相册"。
- 注意：视频编辑器已有分享流程可对齐；改为异步渲染后要保留 `EditorViewModel.exportFile()` 现有的关键节点取消检查与孤儿文件清理逻辑。

### ✅ P1-3 移动 / 重命名失败静默

- `ImportViewModel.moveFile/moveFiles`、`AlbumViewModel.moveFileToGroup`、`GroupManagementSheet` 的重命名/换图标全部忽略失败返回值；空名字直接退出编辑态无提示。
- 注意：失败时**不要**关闭分组选择器/编辑态；返回 Bool 并弹错；空名字给出明确提示。

### ✅ P1-4 视频人脸分析时长与采样

- `VideoFaceAnalyzer` 恒 30fps、无时长预估、无降采样：1 小时视频 ≈ 10.8 万帧 Vision 分析。
- 注意：采样率策略变化会影响检测质量，且与"大视频 premium 门槛"的配额边界联动——改动后要同步配额文案与 `UsageTracker` 边界。

### ✅ P1-5 OCR 检测进度与失败提示

- 检测失败时 `EditorViewModel.errorMessage` 已设置但 UI 不展示（只在导出失败时读取）；长图分片串行 + 最多 4 轮方向识别，全程只有不确定 spinner。
- 注意：`TextRecognizer` 需要加进度回调（分片/轮次）；失败提示复用现有 toast 机制。

### ✅ P1-6 检测结果 chip 与图上框对应

- `BrushEditorComponents.swift:504-535` 的 chip 只显示类型名，与图上橙色框无对应关系（点 chip 不定位）；无批量勾选，只能单个应用或全部应用。
- 注意：若 `SensitiveRegion` 无稳定 id 需要补；建议点 chip 闪烁/高亮对应框 + 多选应用/忽略。

### ✅ P1-7 无障碍欠账

- 多处图标按钮触控目标不足 44pt（密码眼睛按钮、PremiumView 关闭按钮、Restore 文本按钮）；Dynamic Type 大字号下 `ImportActionTile` 标题 `lineLimit(1)+minimumScaleFactor` 被压缩而非放大；全 App 不响应 Reduce Motion；redo 按钮无障碍标签误用了 `action.undoRedaction`（复制粘贴错误，`SimpleBrushEditor.swift:291`）。
- 注意：`PRODUCT.md` 已承诺 WCAG AA 级对比度、44pt、Dynamic Type、Reduce Motion——上架审核可能较真，建议一次性过一遍。

### ✅ P1-8 新手引导

- 首启只有密码设置 sheet，之后直接进导入页，无任何"脱敏如何工作"的引导。
- 注意：与首启密码流程衔接；不要遮挡配额/内购提示；保持"信任、冷静、直接"的产品调性。

### ✅ P1-9 拼接功能

- 超过张数上限时 `StitchViewModel.swift:66-67` 用 `prefix` 静默截断，用户不知道丢了哪几张；手动调整接缝时只有调下部滑块（cropTop）才把置信度置 1，只调上部（cropBottom）橙色低置信警告不消失（`StitchViewModel.swift:89-101`）。
- 注意：截断时要明确告知被丢弃的图片；两个滑块任一移动都应视为人工确认。

### ✅ P1-10 视频导出后台化

- 导出期间退后台/退出被无声杀掉：无 `beginBackgroundTask`/`scenePhase` 处理；`onDisappear` 的 `cleanup()` 会直接取消导出。
- 注意：加后台任务后要防止 `onDisappear` 路径误杀（先判后台任务是否活跃）；可加完成时的本地通知。

### ✅ P1-11 相册异常状态

- 相册缩略图加载失败无标识（`AlbumView.swift:584-586` 永远显示占位图；导入页 grid 有 `exclamationmark.triangle` 失败态可参照）；损坏视频预览黑屏无提示（图片/PDF 有 `showPreviewFailedAlert`，视频没有）。
- 注意：视频预览失败需在解密/加载阶段做校验或失败回调，而不是让播放器静默黑屏。

### ✅ P1-12 视频重复导入"仍然导入"路径

- 图片/PDF 有 `pendingDuplicateSources` + `forceImportPendingDuplicates()` 流程，视频的 `VideoProcessingError.duplicate` 直接进通用错误弹窗。
- 注意：复用现有 pending 机制；注意视频导入现在是可取消 Task 结构（`videoImportTask`），并入 pending 流程时要保持取消语义。

### ✅ P1-13 OCR 区域去重忽略页码（正确性问题）

- `TextRecognizer.swift:160-175` `deduplicateRegions` 只按 boundingBox 相交去重，**不区分 pageIndex**：不同页相同坐标的检测结果会被误删，后页检测可能丢失。
- 注意：这是正确性问题，先写单元测试复现再修（按 `(pageIndex, bounds)` 分组去重）；顺带评估 P1-5 的进度回调一起做。

### ✅ P1-14 视频导出完成态细节

- 导出完成后 `.completed` 面板仍可播放但 "redaction on" 徽标消失（`VideoEditorView.swift:262-274` 只在 `.ready` 显示）；取消导出后无提示，`.cancelled` 面板只有关闭按钮（`retry()` 已存在但无入口）。
- 注意：`.cancelled` 面板加"重试"按钮；完成态保持徽标显示。

### ✅ P1-15 相册删除失败提示不一致

- `AlbumViewModel.deleteFiles`（批量）磁盘清理失败静默，与 `ImportViewModel` 单删路径的提示行为不一致。
- 注意：统一为"失败时非阻塞提示 + 数量"的同一套文案。

---

## P2 及以后（只列要点，不做展开）

- 文件重命名、swipe 操作、分组拖拽排序（`GroupManager.updateGroupsOrder` 写了未接线）
- 多选"移动到分组"按钮（`moveFiles` 已实现未暴露）
- iPad `NavigationSplitView` 适配
- 死代码清理：SwiftData `Item`/ModelContainer（含启动 `fatalError` 风险）、未使用的 `ImageOperationsHandler`/`PDFOperationsHandler`、`ImportManager.batchImport`、大量 debug `print`
- 审核模式 `reviewModeExpiryDate` 上架前续期（当前 2026-08-01 已过期）
- App Store 文案与真实配额对齐（文案"3 图+3 PDF"，实际为 3 媒体+3 文档合计）
- 设置页补"清除所有数据"入口（`resetAllData` 已实现，仅忘记密码路径可达）
