# PDF Support Implementation Plan

## 问题总结

SimpleBrushEditor 无法打开和涂抹PDF文件，原因：
1. EditorViewModel.currentImage 只支持图片文件
2. EditorFactory.getCurrentImage() 对PDF返回nil
3. SimpleBrushEditor 没有PDF页面渲染逻辑

## 解决方案

### 核心思路
将PDF页面渲染为UIImage，复用现有的图片涂抹逻辑，涂抹完成后应用回PDF原始页面。

### 实现步骤

#### Step 1: 扩展 EditorViewModel
**文件**: `EditorViewModel.swift`

**新增属性**:
```swift
// PDF专用属性
@Published var currentPDFDocument: PDFDocument?
@Published var currentPDFPageIndex: Int = 0
@Published var totalPDFPages: Int = 0
```

**新增方法**:
```swift
/// 渲染PDF当前页为UIImage
func renderCurrentPDFPage() -> UIImage? {
    guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
          let document = pdfEditor.pdfDocument,
          let page = document.page(at: currentPDFPageIndex) else {
        return nil
    }
    
    // 使用高分辨率渲染
    let pageRect = page.bounds(for: .mediaBox)
    let scale: CGFloat = 2.0  // 2x分辨率
    let size = CGSize(width: pageRect.width * scale, 
                      height: pageRect.height * scale)
    
    return page.thumbnail(of: size, for: .mediaBox)
}

/// 跳转到指定PDF页面
func goToPDFPage(_ index: Int) {
    guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor else { return }
    
    pdfEditor.goToPage(index)
    currentPDFPageIndex = index
    
    // 更新显示的图片
    if let renderedImage = renderCurrentPDFPage() {
        currentImage = renderedImage
    }
}

/// 检查是否是PDF文件
var isPDFFile: Bool {
    file.fileType == .pdf
}
```

**修改 loadFile()**:
```swift
func loadFile() async {
    // ... 现有代码 ...
    
    try await editor?.loadFile()
    
    // PDF特殊处理
    if file.fileType == .pdf {
        if let pdfEditor = editor?.baseEditor as? PDFRedactionEditor {
            await MainActor.run {
                currentPDFDocument = pdfEditor.pdfDocument
                currentPDFPageIndex = pdfEditor.currentPageIndex
                totalPDFPages = pdfEditor.getTotalPages()
                
                // 渲染PDF页面为图片
                currentImage = renderCurrentPDFPage()
            }
        }
    } else {
        // 图片文件：现有逻辑
        if let image = editor?.getCurrentImage() {
            await MainActor.run {
                currentImage = image
            }
        }
    }
}
```

#### Step 2: 扩展 EditorFactory
**文件**: `EditorFactory.swift`

**修改 AnyRedactionEditor**:
```swift
// 新增属性
let baseEditor: Any  // 保存原始editor实例

init<Editor: RedactionEditor>(_ editor: Editor) {
    self.baseEditor = editor  // 保存原始实例
    
    // ... 现有代码 ...
    
    // 改进getCurrentImage以支持PDF
    self._getCurrentImage = { [weak editor] in
        if let imageEditor = editor as? ImageRedactionEditor {
            return imageEditor.currentImage
        } else if let pdfEditor = editor as? PDFRedactionEditor,
                  let page = pdfEditor.currentPage {
            // PDF: 渲染当前页为图片
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: pageRect.width * scale,
                            height: pageRect.height * scale)
            return page.thumbnail(of: size, for: .mediaBox)
        }
        return nil
    }
}
```

#### Step 3: 扩展 SimpleBrushEditor
**文件**: `SimpleBrushEditor.swift`

**新增PDF页面导航UI**:
```swift
// 在工具栏上方添加页面导航（仅PDF文件显示）
if viewModel.isPDFFile && viewModel.totalPDFPages > 1 {
    HStack {
        Button {
            if viewModel.currentPDFPageIndex > 0 {
                viewModel.goToPDFPage(viewModel.currentPDFPageIndex - 1)
            }
        } label: {
            Image(systemName: "chevron.left")
            Text("上一页")
        }
        .disabled(viewModel.currentPDFPageIndex == 0)
        
        Spacer()
        
        Text("第 \(viewModel.currentPDFPageIndex + 1) / \(viewModel.totalPDFPages) 页")
            .font(.caption)
            .foregroundColor(.secondary)
        
        Spacer()
        
        Button {
            if viewModel.currentPDFPageIndex < viewModel.totalPDFPages - 1 {
                viewModel.goToPDFPage(viewModel.currentPDFPageIndex + 1)
            }
        } label: {
            Text("下一页")
            Image(systemName: "chevron.right")
        }
        .disabled(viewModel.currentPDFPageIndex >= viewModel.totalPDFPages - 1)
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(.systemGray6))
}
```

**修改 applyMosaic() 方法**:
```swift
private func applyMosaic() {
    guard let originalImage = viewModel.currentImage else { return }
    
    // 计算缩放比例
    let scaleX = originalImage.size.width / imageSize.width
    let scaleY = originalImage.size.height / imageSize.height
    
    let effect = selectedEffect.redactionEffect
    
    // 为每条涂抹路径创建包围矩形
    for stroke in brushStrokes {
        guard !stroke.points.isEmpty else { continue }
        
        let xs = stroke.points.map { $0.x }
        let ys = stroke.points.map { $0.y }
        
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        
        let padding: CGFloat = 30
        
        let rect = CGRect(
            x: (minX - padding) * scaleX,
            y: (minY - padding) * scaleY,
            width: (maxX - minX + padding * 2) * scaleX,
            height: (maxY - minY + padding * 2) * scaleY
        )
        
        viewModel.selectedEffect = effect
        viewModel.applyRedaction(at: rect)
    }
    
    // PDF文件：重新渲染当前页
    if viewModel.isPDFFile {
        if let renderedImage = viewModel.renderCurrentPDFPage() {
            viewModel.currentImage = renderedImage
        }
    }
    
    brushStrokes.removeAll()
}
```

## 测试计划

### 测试用例1: PDF打开
- [ ] 选择PDF文件
- [ ] 验证文件成功解密
- [ ] 验证第一页正确渲染为图片
- [ ] 验证总页数显示正确

### 测试用例2: PDF页面导航
- [ ] 点击"下一页"，验证跳转到第2页
- [ ] 点击"上一页"，验证跳转回第1页
- [ ] 验证边界条件（第一页禁用上一页，最后一页禁用下一页）

### 测试用例3: PDF涂抹
- [ ] 在PDF第一页涂抹区域
- [ ] 点击"应用打码"
- [ ] 验证涂抹区域被添加到PDF annotation
- [ ] 切换到第二页涂抹
- [ ] 返回第一页，验证涂抹保留

### 测试用例4: 撤销功能
- [ ] 涂抹PDF后点击"撤销涂抹"
- [ ] 验证涂抹路径被移除
- [ ] 应用打码后点击"撤销打码"
- [ ] 验证PDF annotation被移除

### 测试用例5: 导出PDF
- [ ] 涂抹多个页面
- [ ] 点击"完成"导出
- [ ] 验证导出的PDF包含所有打码标注
- [ ] 在PDF阅读器中打开验证

## 风险评估

### 低风险
- ✅ 复用现有图片涂抹逻辑
- ✅ 不修改核心PDFRedactionEditor逻辑
- ✅ 向后兼容，不影响图片文件

### 中风险
- ⚠️ PDF渲染性能（大文件、高分辨率）
  - 缓解：使用2x分辨率（平衡质量和性能）
  - 缓解：只渲染当前页面，不预加载

### 已知限制
- PDF涂抹精度取决于渲染分辨率
- 大PDF文件（>100页）可能占用较多内存
- PDFKit的annotation不是真正的内容删除（仅视觉遮挡）

## 回滚策略

如果实现出现问题：

1. **回滚EditorViewModel.swift**:
   ```bash
   git checkout HEAD -- EditorViewModel.swift
   ```

2. **回滚EditorFactory.swift**:
   ```bash
   git checkout HEAD -- EditorFactory.swift
   ```

3. **回滚SimpleBrushEditor.swift**:
   ```bash
   git checkout HEAD -- SimpleBrushEditor.swift
   ```

4. **完全回滚**:
   ```bash
   git reset --hard HEAD
   ```

## 时间估算

- Step 1 (EditorViewModel): 15分钟
- Step 2 (EditorFactory): 10分钟
- Step 3 (SimpleBrushEditor): 20分钟
- 测试: 15分钟

**总计**: ~60分钟

## 后续优化（可选）

- [ ] PDF缩略图预览（左侧页面列表）
- [ ] PDF全文搜索和高亮
- [ ] PDF缩放和平移
- [ ] PDF批量打码（一次性处理所有页面）
- [ ] PDF真正的内容删除（需要专业PDF库）
