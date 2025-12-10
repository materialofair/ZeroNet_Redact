# EditorViewModel 重构计划

## 📋 当前状态

- **当前行数**: 758 行
- **复杂度**: 极高
- **职责**: 过多（文件加载、状态管理、PDF操作、图片操作、分组管理、配额管理）

## 🎯 目标

- **目标行数**: 300-350 行
- **策略**: 保持 EditorViewModel 作为协调者，将具体操作委托给专门的处理器

## ✅ 已完成的准备工作

### 1. 已创建的辅助类

#### EditorStateManager.swift
- 状态管理器
- 管理所有 @Published 状态
- 提供状态更新方法

#### PDFOperationsHandler.swift
- PDF 操作处理器
- 页面渲染: `renderCurrentPDFPage()`
- 页面导航: `goToPDFPage(_:)`
- 注释管理: `getCurrentPageAnnotations()`, `findAnnotation(at:)`, `moveAnnotation(at:offset:)`
- 注释操作: `removeAnnotation(at:)`, `scaleAnnotation(at:scale:)`

#### ImageOperationsHandler.swift
- 图片操作处理器
- 区域管理: `getRedactionRegions()`, `findRedactionRegion(at:)`
- 区域操作: `moveRedactionRegion(at:offset:)`, `removeRedactionRegion(at:)`
- 区域缩放: `scaleRedactionRegion(at:scale:)`

## 🔄 重构步骤（分阶段实施）

### 阶段 1: 添加辅助类实例（已完成 ✅）

```swift
// 在 EditorViewModel 中添加
private lazy var pdfOperations: PDFOperationsHandler = {
    PDFOperationsHandler(editor: editor)
}()

private lazy var imageOperations: ImageOperationsHandler = {
    ImageOperationsHandler(editor: editor)
}()
```

### 阶段 2: 重构 PDF 方法（待实施）

**方法映射**:
```swift
// 当前: 直接实现 (50+ 行)
func renderCurrentPDFPage() -> UIImage? {
    // 50 行实现...
}

// 重构后: 委托 (1-3 行)
func renderCurrentPDFPage() -> UIImage? {
    return pdfOperations.renderCurrentPDFPage()
}
```

**需要重构的方法**:
- `renderCurrentPDFPage()` - 50 行 → 1 行
- `goToPDFPage(_:)` - 20 行 → 3 行
- `getCurrentPageAnnotations()` - 10 行 → 1 行
- `findAnnotation(at:)` - 15 行 → 1 行
- `moveAnnotation(at:offset:)` - 30 行 → 3 行
- `removePDFAnnotation(at:)` - 20 行 → 3 行
- `scalePDFAnnotation(at:scale:)` - 20 行 → 3 行

**预计减少**: ~165 行

### 阶段 3: 重构图片方法（待实施）

**需要重构的方法**:
- `getImageRedactionRegions()` - 10 行 → 1 行
- `findImageRedactionRegion(at:)` - 15 行 → 1 行
- `moveImageRedactionRegion(at:offset:)` - 25 行 → 3 行
- `removeImageRedactionRegion(at:)` - 20 行 → 3 行
- `scaleImageRedactionRegion(at:scale:)` - 20 行 → 3 行

**预计减少**: ~90 行

### 阶段 4: 提取分组管理（可选）

**可以创建**: `GroupManagementHandler.swift`

```swift
class GroupManagementHandler {
    func loadGroups() -> [FileGroup]
    func moveToGroup(_ group: FileGroup, file: RedactableFile)
}
```

**预计减少**: ~30 行

### 阶段 5: 提取配额管理（可选）

**可以创建**: `UsageQuotaManager.swift`

```swift
class UsageQuotaManager {
    func canExport() -> Bool
    func recordExportUsage()
    func checkQuotaLimit() -> Bool
}
```

**预计减少**: ~50 行

## 📊 预期效果

| 阶段 | 减少行数 | 累计行数 | 状态 |
|------|---------|---------|------|
| 原始 | - | 758 | - |
| 阶段 1 | +20 | 778 | ✅ 已完成 |
| 阶段 2 | -165 | 613 | ⏳ 待实施 |
| 阶段 3 | -90 | 523 | ⏳ 待实施 |
| 阶段 4 | -30 | 493 | 💡 可选 |
| 阶段 5 | -50 | 443 | 💡 可选 |
| **最终** | **-315** | **~450** | 🎯 目标达成 |

## ⚠️ 风险控制

### 1. 分阶段实施
- 每次只重构一小部分
- 每个阶段后立即测试
- 确保可以随时回滚

### 2. 保持向后兼容
- 不改变公共 API
- 保持相同的调用方式
- 只修改内部实现

### 3. 测试策略
- 每个阶段后手动测试核心流程
- 重点测试 PDF 和图片编辑功能
- 验证撤销/重做功能

## 🔧 实施建议

### 立即可做（低风险）
1. ✅ 创建辅助类（已完成）
2. ⏳ 重构简单的只读方法（如 `isPDFFile`, `isImageFile`）
3. ⏳ 重构工具方法（如 `getCurrentPageAnnotations()`）

### 需要谨慎（中风险）
4. ⏳ 重构状态修改方法（如 `goToPDFPage(_:)`）
5. ⏳ 重构复杂操作（如 `moveAnnotation(at:offset:)`）

### 暂缓实施（高风险）
6. ❌ 导出功能重构（核心业务逻辑，风险太高）
7. ❌ 文件加载重构（初始化逻辑，影响广泛）

## 📝 实施检查清单

每次重构前必须确认：
- [ ] 已备份原始代码
- [ ] 已理解方法的完整功能
- [ ] 已确认所有调用点
- [ ] 已准备测试用例
- [ ] 可以快速回滚

每次重构后必须验证：
- [ ] 编译无错误
- [ ] 手动测试通过
- [ ] 功能行为一致
- [ ] 性能无退化
- [ ] 提交到 Git

## 🎯 下一步行动

### 推荐顺序
1. **先做 AlbumView 重构验证**（已完成，验证效果）
2. **再做 EditorViewModel 阶段 2**（PDF 方法重构）
3. **然后做 阶段 3**（图片方法重构）
4. **评估后决定是否继续阶段 4-5**

### 时间估算
- 阶段 2: 2-3 小时
- 阶段 3: 1-2 小时
- 测试验证: 1 小时
- **总计**: 4-6 小时

## 📚 参考

- SOLID 原则：单一职责原则（SRP）
- 重构模式：委托（Delegation）
- 《重构：改善既有代码的设计》- Martin Fowler
