# PDF打码方块拖拽移动功能设计

## 需求

用户应用打码后，可以点击选中打码方块并拖拽移动到新位置。

## 实现方案

### 架构设计

```
SimpleBrushEditor (UI层)
    ├── 选中状态: selectedAnnotation
    ├── 拖拽手势: DragGesture
    └── 视觉反馈: 选中边框渲染

EditorViewModel (状态管理)
    ├── 选中annotation方法
    ├── 移动annotation方法
    └── 重新渲染PDF

PDFRedactionEditor (PDF操作)
    ├── 查找点击位置的annotation
    ├── 更新annotation的bounds
    └── 刷新PDF页面
```

### 关键数据结构

```swift
// SimpleBrushEditor新增状态
@State private var selectedAnnotationIndex: Int? = nil  // 选中的annotation索引
@State private var isDraggingAnnotation = false
@State private var dragOffset: CGSize = .zero
```

### 实现步骤

#### Step 1: EditorViewModel添加annotation管理方法

```swift
// EditorViewModel.swift

/// 获取当前页面的所有annotations（用于选择和拖拽）
func getCurrentPageAnnotations() -> [(index: Int, bounds: CGRect)] {
    guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
          let page = pdfEditor.currentPage else {
        return []
    }
    
    return page.annotations.enumerated().map { (index, annotation) in
        (index, annotation.bounds)
    }
}

/// 查找点击位置的annotation
func findAnnotation(at point: CGPoint) -> Int? {
    let annotations = getCurrentPageAnnotations()
    
    // 反向查找（最新的annotation在最上层）
    for (index, bounds) in annotations.reversed() {
        if bounds.contains(point) {
            return index
        }
    }
    
    return nil
}

/// 移动annotation到新位置
func moveAnnotation(at index: Int, offset: CGSize) {
    guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
          let page = pdfEditor.currentPage,
          index < page.annotations.count else {
        print("⚠️ moveAnnotation: 索引超出范围")
        return
    }
    
    let annotation = page.annotations[index]
    let currentBounds = annotation.bounds
    
    // 计算新位置
    let newBounds = CGRect(
        x: currentBounds.origin.x + offset.width,
        y: currentBounds.origin.y + offset.height,
        width: currentBounds.width,
        height: currentBounds.height
    )
    
    annotation.bounds = newBounds
    
    // 重新渲染
    if let renderedImage = renderCurrentPDFPage() {
        currentImage = renderedImage
    }
    
    print("📍 moveAnnotation: 索引\(index) 移动到 \(newBounds)")
}
```

#### Step 2: SimpleBrushEditor添加选择和拖拽UI

```swift
// SimpleBrushEditor.swift

// 新增状态
@State private var selectedAnnotationIndex: Int? = nil
@State private var isDraggingAnnotation = false
@State private var dragOffset: CGSize = .zero

// 在imageCanvas中添加annotation选择层
// 在Canvas下方添加一个透明手势层用于检测点击
.overlay(
    Color.clear
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDraggingAnnotation {
                        // 检测是否点击在annotation上
                        let screenPoint = value.location
                        
                        // 转换为PDF坐标
                        if viewModel.isPDFFile {
                            let pdfPoint = convertScreenToPDFCoordinate(
                                screenPoint: screenPoint,
                                displaySize: displaySize
                            )
                            
                            if let index = viewModel.findAnnotation(at: pdfPoint) {
                                selectedAnnotationIndex = index
                                isDraggingAnnotation = true
                                dragOffset = .zero
                            }
                        }
                    } else {
                        // 正在拖拽
                        dragOffset = CGSize(
                            width: value.translation.width,
                            height: value.translation.height
                        )
                    }
                }
                .onEnded { _ in
                    if isDraggingAnnotation, let index = selectedAnnotationIndex {
                        // 转换拖拽偏移到PDF坐标
                        let pdfOffset = convertScreenOffsetToPDFOffset(
                            screenOffset: dragOffset,
                            displaySize: displaySize
                        )
                        
                        viewModel.moveAnnotation(at: index, offset: pdfOffset)
                        
                        isDraggingAnnotation = false
                        dragOffset = .zero
                    }
                }
        )
)

// 坐标转换辅助方法
private func convertScreenToPDFCoordinate(screenPoint: CGPoint, displaySize: CGSize) -> CGPoint {
    guard let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
          let page = pdfEditor.currentPage else {
        return screenPoint
    }
    
    let pageRect = page.bounds(for: .mediaBox)
    let scaleX = pageRect.width / displaySize.width
    let scaleY = pageRect.height / displaySize.height
    
    let pdfX = screenPoint.x * scaleX
    let pdfY = pageRect.height - (screenPoint.y * scaleY)  // Y轴翻转
    
    return CGPoint(x: pdfX, y: pdfY)
}

private func convertScreenOffsetToPDFOffset(screenOffset: CGSize, displaySize: CGSize) -> CGSize {
    guard let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
          let page = pdfEditor.currentPage else {
        return screenOffset
    }
    
    let pageRect = page.bounds(for: .mediaBox)
    let scaleX = pageRect.width / displaySize.width
    let scaleY = pageRect.height / displaySize.height
    
    return CGSize(
        width: screenOffset.width * scaleX,
        height: -screenOffset.height * scaleY  // Y轴翻转
    )
}
```

#### Step 3: 添加选中状态视觉反馈

```swift
// 在Canvas中绘制选中边框
if let selectedIndex = selectedAnnotationIndex,
   let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
   let page = pdfEditor.currentPage,
   selectedIndex < page.annotations.count {
    
    let annotation = page.annotations[selectedIndex]
    var bounds = annotation.bounds
    
    // 如果正在拖拽，添加偏移
    if isDraggingAnnotation {
        bounds = CGRect(
            x: bounds.origin.x + dragOffset.width,
            y: bounds.origin.y + dragOffset.height,
            width: bounds.width,
            height: bounds.height
        )
    }
    
    // 转换为屏幕坐标绘制选中边框
    let screenBounds = convertPDFBoundsToScreen(bounds, displaySize: displaySize)
    
    context.stroke(
        Path(roundedRect: screenBounds, cornerRadius: 4),
        with: .color(.blue),
        lineWidth: 3
    )
}
```

## 测试计划

### 测试用例1: 选中annotation
- [ ] 点击打码方块
- [ ] 验证方块显示蓝色边框
- [ ] 点击空白区域，边框消失

### 测试用例2: 拖拽annotation
- [ ] 选中方块后拖动
- [ ] 验证方块跟随手指移动
- [ ] 松手后方块固定在新位置

### 测试用例3: 多个annotation
- [ ] 添加多个打码方块
- [ ] 选中和拖拽不同的方块
- [ ] 验证互不干扰

### 测试用例4: 跨页面
- [ ] 在第1页添加打码
- [ ] 切换到第2页
- [ ] 返回第1页，验证打码位置不变

### 测试用例5: 边界条件
- [ ] 拖拽到页面边缘
- [ ] 验证不超出页面范围

## 风险评估

### 低风险
- ✅ 纯UI功能，不影响核心打码逻辑
- ✅ 向后兼容，不拖拽也能正常使用

### 中风险
- ⚠️ 坐标转换复杂（屏幕↔PDF）
  - 缓解：详细测试和日志

### 已知限制
- 暂不支持多选拖拽
- 暂不支持调整大小

## 时间估算

- Step 1 (EditorViewModel): 20分钟
- Step 2 (SimpleBrushEditor UI): 30分钟
- Step 3 (视觉反馈): 15分钟
- 测试: 15分钟

**总计**: ~80分钟
