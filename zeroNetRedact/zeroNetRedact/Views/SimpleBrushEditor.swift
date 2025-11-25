//
//  SimpleBrushEditor.swift
//  ZeroNet Redact
//
//  超简单的涂抹编辑器 - 手指涂抹打码，可撤销
//

import PDFKit
import SwiftUI

/// 涂抹路径
struct BrushStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
}

/// 涂抹效果类型
enum BrushEffect: String, CaseIterable {
    case mosaic
    case black
    case white
    case blur

    var localizedName: String {
        switch self {
        case .mosaic: return NSLocalizedString("effect.mosaic", comment: "")
        case .black: return NSLocalizedString("effect.black", comment: "")
        case .white: return NSLocalizedString("effect.white", comment: "")
        case .blur: return NSLocalizedString("effect.blur", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .mosaic: return "square.grid.3x3.fill"
        case .black: return "square.fill"
        case .white: return "square"
        case .blur: return "circle.dotted"
        }
    }

    var previewColor: Color {
        switch self {
        case .mosaic: return .gray
        case .black: return .black
        case .white: return .white
        case .blur: return .blue
        }
    }

    var redactionEffect: RedactionEffect {
        switch self {
        case .mosaic: return .mosaic(pixelSize: 20)
        case .black: return .solidBlack
        case .white: return .rectangle(color: .white, opacity: 1.0)
        case .blur: return .blur(radius: 10)
        }
    }
}

/// 简单涂抹编辑器
struct SimpleBrushEditor: View {
    let file: RedactableFile
    @StateObject private var viewModel: EditorViewModel
    @State private var brushStrokes: [BrushStroke] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var imageSize: CGSize = .zero
    @State private var selectedEffect: BrushEffect = .black
    @State private var isInitialLoad = true  // 新增:追踪是否是初次加载
    @Environment(\.dismiss) private var dismiss

    // MARK: - Drag Annotation State
    @State private var isDragMode: Bool = false
    @State private var selectedAnnotationIndex: Int? = nil
    @State private var dragStartLocation: CGPoint = .zero
    @State private var currentDragOffset: CGSize = .zero
    @State private var isDraggingRegion: Bool = false  // 是否正在拖拽移动区域

    // MARK: - Scale Step Constants
    private let scaleStep: CGFloat = 1.1  // 每次放大/缩小10%

    // MARK: - Computed Properties

    /// 检查是否有可缩放的脱敏区域
    private var hasRedactionRegions: Bool {
        if viewModel.isPDFFile {
            return viewModel.getPDFAnnotationCount() > 0
        } else if viewModel.isImageFile {
            return !viewModel.getImageRedactionRegions().isEmpty
        }
        return false
    }

    init(file: RedactableFile) {
        self.file = file
        _viewModel = StateObject(wrappedValue: EditorViewModel(file: file))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 主编辑区域
                GeometryReader { geometry in
                    ZStack {
                        // 白色背景，避免黑屏
                        Color.white

                        // 浅灰色背景层
                        Color.black.opacity(0.05)

                        if isInitialLoad || viewModel.isLoading {
                            // 加载状态（包括初次加载和后续加载）
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.blue)
                                Text(NSLocalizedString("editor.loading", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white)
                        } else if let image = viewModel.currentImage {
                            // 图片已加载 - 使用ZStack覆盖层布局
                            ZStack(alignment: .leading) {
                                // 主画布区域（全屏）
                                imageCanvas(image: image, geometry: geometry)

                                // 左侧缩放控制条（有脱敏区域时显示，覆盖在画布上方）
                                if hasRedactionRegions {
                                    scaleControlBar
                                        .transition(.move(edge: .leading).combined(with: .opacity))
                                }
                            }
                            .animation(
                                .easeInOut(duration: 0.2),
                                value: hasRedactionRegions)
                        } else {
                            // 加载失败
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 50))
                                    .foregroundColor(.orange)
                                Text(NSLocalizedString("editor.loadFailed", comment: ""))
                                    .font(.headline)
                                Text(NSLocalizedString("editor.loadFailedHint", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white)
                        }
                    }
                }

                // 底部工具栏
                VStack(spacing: 0) {
                    // PDF页面导航栏（仅PDF文件显示）
                    if viewModel.isPDFFile && viewModel.totalPDFPages > 1 {
                        HStack(spacing: 16) {
                            Button {
                                if viewModel.currentPDFPageIndex > 0 {
                                    viewModel.goToPDFPage(viewModel.currentPDFPageIndex - 1)
                                    brushStrokes.removeAll()
                                    currentStroke.removeAll()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.caption)
                                    Text(NSLocalizedString("pdf.prevPage", comment: ""))
                                        .font(.subheadline)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.currentPDFPageIndex == 0)

                            Spacer()

                            VStack(spacing: 2) {
                                Text(
                                    String(
                                        format: NSLocalizedString("pdf.pageInfo", comment: ""),
                                        viewModel.currentPDFPageIndex + 1,
                                        viewModel.totalPDFPages
                                    )
                                )
                                .font(.headline)
                                Text(NSLocalizedString("pdf.switchHint", comment: ""))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                if viewModel.currentPDFPageIndex < viewModel.totalPDFPages - 1 {
                                    viewModel.goToPDFPage(viewModel.currentPDFPageIndex + 1)
                                    brushStrokes.removeAll()
                                    currentStroke.removeAll()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(NSLocalizedString("pdf.nextPage", comment: ""))
                                        .font(.subheadline)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.currentPDFPageIndex >= viewModel.totalPDFPages - 1)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))

                        Divider()
                    }

                    // 效果选择栏
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("effect.label", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(BrushEffect.allCases, id: \.self) { effect in
                                    Button {
                                        selectedEffect = effect
                                    } label: {
                                        VStack(spacing: 4) {
                                            ZStack {
                                                Circle()
                                                    .fill(
                                                        selectedEffect == effect
                                                            ? Color.accentColor
                                                            : Color(.systemGray5)
                                                    )
                                                    .frame(width: 40, height: 40)

                                                Image(systemName: effect.icon)
                                                    .font(.body)
                                                    .foregroundColor(
                                                        selectedEffect == effect
                                                            ? .white : effect.previewColor)
                                            }

                                            Text(effect.localizedName)
                                                .font(.system(size: 11))
                                                .fontWeight(
                                                    selectedEffect == effect ? .semibold : .regular
                                                )
                                                .foregroundColor(
                                                    selectedEffect == effect
                                                        ? .accentColor : .primary
                                                )
                                                .lineLimit(1)
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .frame(width: 55)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 8)

                    Divider()
                        .padding(.vertical, 8)

                    // 操作按钮栏
                    HStack(spacing: 8) {
                        // 模式切换按钮
                        Button {
                            isDragMode.toggle()
                            selectedAnnotationIndex = nil
                            currentDragOffset = .zero
                            if isDragMode {
                                brushStrokes.removeAll()
                                currentStroke.removeAll()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(
                                    systemName: isDragMode
                                        ? "hand.draw.fill" : "hand.point.up.left.fill"
                                )
                                .font(.caption)
                                Text(
                                    NSLocalizedString(
                                        isDragMode ? "mode.brush" : "mode.drag", comment: "")
                                )
                                .font(.caption2)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(isDragMode ? .orange : .blue)

                        // 撤销涂抹
                        Button {
                            undoLastStroke()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .disabled(brushStrokes.isEmpty || isDragMode)

                        // 撤销打码
                        Button {
                            viewModel.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canUndo)

                        Spacer()

                        // 应用打码按钮
                        Button {
                            applyMosaic()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.callout)
                                Text(NSLocalizedString("action.applyRedaction", comment: ""))
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(brushStrokes.isEmpty || isDragMode)

                        // 导出按钮
                        Button {
                            Task {
                                if !brushStrokes.isEmpty {
                                    print("📝 完成按钮: 自动应用\(brushStrokes.count)个未应用的打码")
                                    applyMosaic()
                                }
                                await viewModel.exportFile()
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.callout)
                                Text(NSLocalizedString("editor.done", comment: ""))
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle(NSLocalizedString("editor.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("editor.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Button(action: {
                        viewModel.showGroupPicker = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.currentGroup?.iconName ?? "folder.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(
                                viewModel.currentGroup?.name
                                    ?? NSLocalizedString("group.default", comment: "")
                            )
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                    }
                }
            }
            .sheet(isPresented: $viewModel.showGroupPicker) {
                GroupPickerSheet(viewModel: viewModel)
            }
            .task {
                print("🔵 SimpleBrushEditor: .task 开始执行")
                await viewModel.loadFile()
                isInitialLoad = false  // 加载完成后，设置为false
                print("🔵 SimpleBrushEditor: .task 执行完成，isInitialLoad = false")
            }
            .background(Color.white)  // 确保整个视图背景是白色
        }
        .navigationViewStyle(.stack)  // 使用stack样式，避免iPad的分栏问题
        .accentColor(.blue)  // 设置强调色
    }

    // MARK: - Scale Control Bar

    /// 左侧缩放控制条
    private var scaleControlBar: some View {
        let hasSelection = selectedAnnotationIndex != nil

        return VStack(spacing: 8) {
            // 标题
            Text(NSLocalizedString("scale.title", comment: "缩放"))
                .font(.caption2)
                .foregroundColor(.secondary)

            // 提示：需要先开启拖拽模式并选中区域
            if !isDragMode {
                Text(NSLocalizedString("scale.enableDragHint", comment: "开启拖拽"))
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            } else if !hasSelection {
                Text(NSLocalizedString("scale.selectHint", comment: "点击选中"))
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // 放大按钮
            Button {
                if let index = selectedAnnotationIndex {
                    viewModel.scaleRedactionRegion(at: index, scale: scaleStep)
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(hasSelection ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)

            // 缩放指示器
            VStack(spacing: 3) {
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(hasSelection ? (0.3 + Double(4 - i) * 0.15) : 0.2))
                        .frame(width: 14, height: 3)
                }
            }
            .padding(.vertical, 6)

            // 缩小按钮
            Button {
                if let index = selectedAnnotationIndex {
                    viewModel.scaleRedactionRegion(at: index, scale: 1.0 / scaleStep)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundColor(hasSelection ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)

            Spacer()

            // 删除选中区域按钮
            Button {
                if let index = selectedAnnotationIndex {
                    if viewModel.isPDFFile {
                        viewModel.removePDFAnnotation(at: index)
                    } else if viewModel.isImageFile {
                        viewModel.removeImageRedactionRegion(at: index)
                    }
                    selectedAnnotationIndex = nil
                }
            } label: {
                Image(systemName: "trash.circle.fill")
                    .font(.title2)
                    .foregroundColor(hasSelection ? .red : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(width: 50)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground).opacity(0.95))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 2, y: 0)
        )
        .padding(.leading, 8)
        .padding(.vertical, 20)
    }

    // MARK: - Image Canvas

    private func imageCanvas(image: UIImage, geometry: GeometryProxy) -> some View {
        let displaySize = calculateDisplaySize(for: image.size, in: geometry.size)

        return ZStack {
            // 原始图片
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: displaySize.width, height: displaySize.height)
                .onAppear {
                    imageSize = displaySize
                }

            // 涂抹路径（红色显示）和注释边框
            Canvas { context, size in
                // 绘制已完成的涂抹
                for stroke in brushStrokes {
                    var path = Path()
                    if let first = stroke.points.first {
                        path.move(to: first)
                        for point in stroke.points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    context.stroke(
                        path,
                        with: .color(.red.opacity(0.6)),
                        lineWidth: 40
                    )
                }

                // 绘制当前正在进行的涂抹
                if !currentStroke.isEmpty {
                    var path = Path()
                    if let first = currentStroke.first {
                        path.move(to: first)
                        for point in currentStroke.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    context.stroke(
                        path,
                        with: .color(.red.opacity(0.4)),
                        lineWidth: 40
                    )
                }

                // 拖拽模式：显示所有脱敏区域边框
                if isDragMode {
                    if viewModel.isPDFFile {
                        // PDF: 显示PDF注释边框
                        let annotations = viewModel.getCurrentPageAnnotations()
                        for (index, pdfBounds) in annotations {
                            if let screenRect = pdfRectToScreen(pdfBounds) {
                                var rect = screenRect

                                // 如果是选中的注释，应用拖拽偏移
                                if index == selectedAnnotationIndex {
                                    rect = rect.offsetBy(
                                        dx: currentDragOffset.width,
                                        dy: currentDragOffset.height
                                    )
                                }

                                let borderPath = Path(
                                    roundedRect: rect,
                                    cornerRadius: 4
                                )

                                // 选中的注释用蓝色粗边框，其他用绿色细边框
                                if index == selectedAnnotationIndex {
                                    context.stroke(
                                        borderPath,
                                        with: .color(.blue),
                                        lineWidth: 3
                                    )
                                } else {
                                    context.stroke(
                                        borderPath,
                                        with: .color(.green.opacity(0.6)),
                                        lineWidth: 2
                                    )
                                }
                            }
                        }
                    } else if viewModel.isImageFile {
                        // 图片: 显示图片脱敏区域边框
                        let regions = viewModel.getImageRedactionRegions()
                        for (index, imageBounds) in regions {
                            if let screenRect = imageRectToScreen(imageBounds) {
                                var rect = screenRect

                                // 如果是选中的区域，应用拖拽偏移
                                if index == selectedAnnotationIndex {
                                    rect = rect.offsetBy(
                                        dx: currentDragOffset.width,
                                        dy: currentDragOffset.height
                                    )
                                }

                                let borderPath = Path(
                                    roundedRect: rect,
                                    cornerRadius: 4
                                )

                                // 选中的区域用蓝色粗边框，其他用绿色细边框
                                if index == selectedAnnotationIndex {
                                    context.stroke(
                                        borderPath,
                                        with: .color(.blue),
                                        lineWidth: 3
                                    )
                                } else {
                                    context.stroke(
                                        borderPath,
                                        with: .color(.green.opacity(0.6)),
                                        lineWidth: 2
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let location = value.location

                        // 检查是否在画布范围内
                        guard
                            location.x >= 0 && location.x <= displaySize.width
                                && location.y >= 0 && location.y <= displaySize.height
                        else {
                            return
                        }

                        if isDragMode {
                            // 拖拽模式：选中或移动脱敏区域

                            if isDraggingRegion {
                                // 正在拖拽中：更新偏移量
                                currentDragOffset = CGSize(
                                    width: location.x - dragStartLocation.x,
                                    height: location.y - dragStartLocation.y
                                )
                            } else {
                                // 开始新的手势：查找点击位置的脱敏区域
                                var tappedIndex: Int? = nil
                                if viewModel.isPDFFile {
                                    if let pdfPoint = screenToPDF(location) {
                                        tappedIndex = viewModel.findAnnotation(at: pdfPoint)
                                    }
                                } else if viewModel.isImageFile {
                                    if let imagePoint = screenToImage(location) {
                                        tappedIndex = viewModel.findImageRedactionRegion(
                                            at: imagePoint)
                                    }
                                }

                                if let index = tappedIndex {
                                    // 点击了某个脱敏区域：选中并开始拖拽
                                    selectedAnnotationIndex = index
                                    dragStartLocation = location
                                    currentDragOffset = .zero
                                    isDraggingRegion = true
                                } else {
                                    // 点击空白区域：取消选中
                                    selectedAnnotationIndex = nil
                                    currentDragOffset = .zero
                                }
                            }
                        } else {
                            // 涂抹模式：正常绘制
                            currentStroke.append(location)
                        }
                    }
                    .onEnded { _ in
                        if isDragMode {
                            // 拖拽模式：应用偏移并刷新
                            if let index = selectedAnnotationIndex {
                                if viewModel.isPDFFile,
                                    let pdfEditor = viewModel.editor?.baseEditor
                                        as? PDFRedactionEditor,
                                    let page = pdfEditor.currentPage
                                {
                                    // PDF: 转换到PDF坐标系
                                    let pageRect = page.bounds(for: .mediaBox)
                                    let pdfPageWidth = pageRect.width
                                    let pdfPageHeight = pageRect.height

                                    // 计算缩放比例
                                    let pdfScaleX = pdfPageWidth / imageSize.width
                                    let pdfScaleY = pdfPageHeight / imageSize.height

                                    // 偏移量转换：只需缩放，Y方向需要翻转（屏幕向下=PDF向上）
                                    let pdfDelta = CGSize(
                                        width: currentDragOffset.width * pdfScaleX,
                                        height: -currentDragOffset.height * pdfScaleY  // Y方向相反
                                    )

                                    print(
                                        "🔍 PDF拖拽偏移: 屏幕(\(currentDragOffset.width), \(currentDragOffset.height)) -> PDF(\(pdfDelta.width), \(pdfDelta.height))"
                                    )

                                    viewModel.moveAnnotation(at: index, offset: pdfDelta)
                                } else if viewModel.isImageFile {
                                    // 图片: 转换到图片像素坐标系
                                    guard let originalImage = viewModel.currentImage else { return }

                                    // 计算缩放比例（原始图片像素 / 屏幕显示尺寸）
                                    let imageScaleX = originalImage.size.width / imageSize.width
                                    let imageScaleY = originalImage.size.height / imageSize.height

                                    // 偏移量转换：屏幕偏移 -> 图片像素偏移
                                    let imageDelta = CGSize(
                                        width: currentDragOffset.width * imageScaleX,
                                        height: currentDragOffset.height * imageScaleY  // 图片坐标系与屏幕同向
                                    )

                                    print(
                                        "🔍 图片拖拽偏移: 屏幕(\(currentDragOffset.width), \(currentDragOffset.height)) -> 图片(\(imageDelta.width), \(imageDelta.height))"
                                    )

                                    viewModel.moveImageRedactionRegion(
                                        at: index, offset: imageDelta)
                                }
                            }

                            // 重置拖拽状态，但保持选中状态以便用户使用缩放控制条
                            // selectedAnnotationIndex 保持不变
                            currentDragOffset = .zero
                            isDraggingRegion = false  // 拖拽结束
                        } else {
                            // 涂抹模式：保存笔画
                            if !currentStroke.isEmpty {
                                brushStrokes.append(BrushStroke(points: currentStroke))
                                currentStroke = []
                            }
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// 撤销最后一笔涂抹
    private func undoLastStroke() {
        if !brushStrokes.isEmpty {
            brushStrokes.removeLast()
        }
    }

    // MARK: - Coordinate Conversion Helpers

    /// 屏幕坐标转PDF坐标(含Y轴翻转)
    private func screenToPDF(_ screenPoint: CGPoint) -> CGPoint? {
        guard viewModel.isPDFFile,
            let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let pdfPageWidth = pageRect.width
        let pdfPageHeight = pageRect.height

        let pdfScaleX = pdfPageWidth / imageSize.width
        let pdfScaleY = pdfPageHeight / imageSize.height

        let pdfX = screenPoint.x * pdfScaleX
        let pdfY = screenPoint.y * pdfScaleY

        // Y轴翻转
        let flippedY = pdfPageHeight - pdfY

        return CGPoint(x: pdfX, y: flippedY)
    }

    /// PDF坐标转屏幕坐标(含Y轴翻转)
    private func pdfToScreen(_ pdfPoint: CGPoint) -> CGPoint? {
        guard viewModel.isPDFFile,
            let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let pdfPageWidth = pageRect.width
        let pdfPageHeight = pageRect.height

        let screenScaleX = imageSize.width / pdfPageWidth
        let screenScaleY = imageSize.height / pdfPageHeight

        // Y轴翻转
        let flippedY = pdfPageHeight - pdfPoint.y

        let screenX = pdfPoint.x * screenScaleX
        let screenY = flippedY * screenScaleY

        return CGPoint(x: screenX, y: screenY)
    }

    /// PDF矩形转屏幕矩形
    private func pdfRectToScreen(_ pdfRect: CGRect) -> CGRect? {
        guard let topLeft = pdfToScreen(CGPoint(x: pdfRect.minX, y: pdfRect.maxY)),
            let bottomRight = pdfToScreen(CGPoint(x: pdfRect.maxX, y: pdfRect.minY))
        else {
            return nil
        }

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    // MARK: - Image Coordinate Conversion Helpers

    /// 屏幕坐标转图片像素坐标
    private func screenToImage(_ screenPoint: CGPoint) -> CGPoint? {
        guard viewModel.isImageFile,
            let originalImage = viewModel.currentImage
        else {
            return nil
        }

        // 计算缩放比例（原始图片像素 / 屏幕显示尺寸）
        let scaleX = originalImage.size.width / imageSize.width
        let scaleY = originalImage.size.height / imageSize.height

        let imageX = screenPoint.x * scaleX
        let imageY = screenPoint.y * scaleY

        return CGPoint(x: imageX, y: imageY)
    }

    /// 图片像素坐标转屏幕坐标
    private func imageToScreen(_ imagePoint: CGPoint) -> CGPoint? {
        guard viewModel.isImageFile,
            let originalImage = viewModel.currentImage
        else {
            return nil
        }

        // 计算缩放比例（屏幕显示尺寸 / 原始图片像素）
        let scaleX = imageSize.width / originalImage.size.width
        let scaleY = imageSize.height / originalImage.size.height

        let screenX = imagePoint.x * scaleX
        let screenY = imagePoint.y * scaleY

        return CGPoint(x: screenX, y: screenY)
    }

    /// 图片像素矩形转屏幕矩形
    private func imageRectToScreen(_ imageRect: CGRect) -> CGRect? {
        guard let topLeft = imageToScreen(CGPoint(x: imageRect.minX, y: imageRect.minY)),
            let bottomRight = imageToScreen(CGPoint(x: imageRect.maxX, y: imageRect.maxY))
        else {
            return nil
        }

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    /// 应用马赛克到涂抹区域
    private func applyMosaic() {
        guard let originalImage = viewModel.currentImage else { return }

        // 计算缩放比例
        let scaleX = originalImage.size.width / imageSize.width
        let scaleY = originalImage.size.height / imageSize.height

        // 获取当前选中的效果
        let effect = selectedEffect.redactionEffect

        // 为每条涂抹路径创建一个包围矩形
        for stroke in brushStrokes {
            guard !stroke.points.isEmpty else { continue }

            let xs = stroke.points.map { $0.x }
            let ys = stroke.points.map { $0.y }

            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0

            // 涂抹线宽
            let brushWidth: CGFloat = 40
            // padding为线宽的一半，确保完全覆盖涂抹路径
            let padding: CGFloat = brushWidth / 2

            var rect: CGRect

            // PDF特殊处理：坐标系原点在左下角，需要Y轴翻转
            if viewModel.isPDFFile {
                // 获取PDF页面的实际尺寸
                guard let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
                    let page = pdfEditor.currentPage
                else {
                    print("⚠️ 无法获取PDF页面信息")
                    continue
                }

                let pageRect = page.bounds(for: .mediaBox)
                let pdfPageWidth = pageRect.width
                let pdfPageHeight = pageRect.height

                // 关键修复：直接计算屏幕到PDF原始页面的比例
                // 不使用scaleX/scaleY（那是渲染图片的比例）
                let pdfScaleX = pdfPageWidth / imageSize.width
                let pdfScaleY = pdfPageHeight / imageSize.height

                // 计算在PDF坐标系中的位置
                let pdfX = (minX - padding) * pdfScaleX
                let pdfY = (minY - padding) * pdfScaleY
                let pdfWidth = (maxX - minX + padding * 2) * pdfScaleX
                let pdfHeight = (maxY - minY + padding * 2) * pdfScaleY

                // Y轴翻转：PDF原点在左下角
                let flippedY = pdfPageHeight - pdfY - pdfHeight

                rect = CGRect(
                    x: pdfX,
                    y: flippedY,
                    width: pdfWidth,
                    height: pdfHeight
                )

                print(
                    "📍 PDF涂抹: 屏幕(\(minX),\(minY)) PDF页(\(pdfPageWidth)x\(pdfPageHeight)) 显示(\(imageSize.width)x\(imageSize.height)) scale(\(pdfScaleX)) -> PDF坐标(\(pdfX),\(flippedY))"
                )
            } else {
                // 图片：正常坐标系（原点在左上角）
                rect = CGRect(
                    x: (minX - padding) * scaleX,
                    y: (minY - padding) * scaleY,
                    width: (maxX - minX + padding * 2) * scaleX,
                    height: (maxY - minY + padding * 2) * scaleY
                )
            }

            // 使用选中的效果
            viewModel.selectedEffect = effect
            viewModel.applyRedaction(at: rect)
        }

        // 清空涂抹路径
        brushStrokes.removeAll()

        // PDF文件：重新渲染当前页显示最新的打码效果
        if viewModel.isPDFFile {
            if let renderedImage = viewModel.renderCurrentPDFPage() {
                viewModel.currentImage = renderedImage
            }
        }
    }

    /// 计算图片显示尺寸
    private func calculateDisplaySize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
}
