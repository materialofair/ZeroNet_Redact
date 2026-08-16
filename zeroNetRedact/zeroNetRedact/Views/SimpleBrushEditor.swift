//
//  SimpleBrushEditor.swift
//  ZeroNet Redact
//
//  超简单的涂抹编辑器 - 手指涂抹打码，可撤销
//

import PDFKit
import SwiftUI

/// 简单涂抹编辑器
struct SimpleBrushEditor: View {
    let file: RedactableFile
    @StateObject private var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Brush State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var brushStrokes: [BrushStroke] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var paintGestureStart: CGPoint = .zero
    @State private var imageSize: CGSize = .zero
    @State private var selectedEffect: BrushEffect = .black
    @State private var selectedBrushSize: BrushSize = .medium
    @State private var isInitialLoad = true

    // MARK: - Canvas Mode State
    @State private var canvasMode: CanvasMode = .brush
    @State private var selectedAnnotationIndex: Int? = nil
    @State private var dragStartLocation: CGPoint = .zero
    @State private var currentDragOffset: CGSize = .zero
    @State private var isDraggingRegion: Bool = false

    // MARK: - Detection Selection State
    /// 多选中的检测区域 id（chip 与图上橙色框联动）
    @State private var selectedDetectedIDs: Set<UUID> = []
    /// 点击 chip 时闪烁高亮的区域 id（短暂放大描边定位）
    @State private var flashRegionID: UUID? = nil

    // MARK: - Zoom & Pan State
    @State private var canvasScale: CGFloat = 1.0
    @State private var lastCanvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero
    @State private var lastCanvasOffset: CGSize = .zero

    // MARK: - Export State
    @State private var exportTask: Task<Void, Never>?
    @State private var showShareSheet = false

    // MARK: - Toast State
    @State private var toastMessage: String? = nil
    @State private var toastIsSuccess: Bool = true

    // MARK: - UI State
    @State private var isScaleBarVisible: Bool = true
    @State private var showDiscardConfirm: Bool = false
    @State private var showRotateConfirm: Bool = false

    // MARK: - Constants
    private let scaleStep: CGFloat = 1.1
    private let minCanvasScale: CGFloat = 1.0
    private let maxCanvasScale: CGFloat = 4.0
    private let toastDisplayDurationNanoseconds: UInt64 = 1_500_000_000

    private var brushWidth: CGFloat { selectedBrushSize.width }

    // MARK: - Computed Properties

    private var hasRedactionRegions: Bool {
        if viewModel.isPDFFile {
            return viewModel.getPDFAnnotationCount() > 0
        } else if viewModel.isImageFile {
            return !viewModel.getImageRedactionRegions().isEmpty
        }
        return false
    }

    /// 是否存在未导出的编辑内容（未应用的涂抹或已应用但未导出的脱敏区域）
    private var hasUnsavedWork: Bool {
        !brushStrokes.isEmpty || viewModel.canUndo
    }

    private var coordinateConverter: CoordinateConverter {
        CoordinateConverter(imageSize: imageSize, viewModel: viewModel)
    }

    // MARK: - Initialization

    init(file: RedactableFile) {
        self.file = file
        _viewModel = StateObject(wrappedValue: EditorViewModel(file: file))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 主编辑区域
                editorContent

                // 底部工具栏
                bottomToolbar
            }
            .navigationTitle(NSLocalizedString("editor.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigationToolbar }
            .task {
                await viewModel.loadFile()
                isInitialLoad = false
            }
            .background(Color.white)
        }
        .accentColor(.blue)
        .overlay(alignment: .top) { toastOverlay }
        .interactiveDismissDisabled(hasUnsavedWork)
        .confirmationDialog(
            NSLocalizedString("editor.discardConfirm.title", comment: ""),
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("editor.discardConfirm.discard", comment: ""), role: .destructive) {
                exportTask?.cancel()
                dismiss()
            }
            Button(NSLocalizedString("editor.discardConfirm.keepEditing", comment: ""), role: .cancel) {}
        }
        .alert(
            NSLocalizedString("usage.limit.title", comment: ""),
            isPresented: $viewModel.showUsageLimitAlert
        ) {
            Button(NSLocalizedString("usage.limit.upgrade", comment: "")) {
                viewModel.showPremiumView = true
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("usage.limit.message", comment: ""))
        }
        .alert(
            NSLocalizedString("editor.rotateConfirm.title", comment: ""),
            isPresented: $showRotateConfirm
        ) {
            Button(NSLocalizedString("editor.rotateConfirm.rotateAnyway", comment: ""), role: .destructive) {
                if let image = viewModel.currentImage {
                    performRotate(image)
                }
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("editor.rotateConfirm.message", comment: ""))
        }
        .sheet(
            isPresented: $viewModel.showPremiumView,
            onDismiss: {
                // 购买成功后自动重试导出
                if AppState.shared.hasUnlimitedAccess {
                    performExport()
                }
            }
        ) {
            PremiumView()
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            // 分享结束（保存/发送/取消）后关闭编辑器
            dismiss()
        }) {
            if let url = viewModel.exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Editor Content

    @ViewBuilder
    private var editorContent: some View {
        ZStack {
            Color.white
            Color.black.opacity(0.05)

            if isInitialLoad || viewModel.isLoading {
                EditorLoadingView()
            } else if let image = viewModel.currentImage {
                // 控制栏占据布局而非悬浮遮挡:栏出现时图片区域变窄,
                // 图片等比缩小完整可见;栏隐藏时恢复满宽
                HStack(spacing: 0) {
                    if hasRedactionRegions && isScaleBarVisible {
                        ScaleControlBar(
                            isDragMode: canvasMode == .drag,
                            hasSelection: selectedAnnotationIndex != nil,
                            onScaleUp: { scaleSelectedRegion(scale: scaleStep) },
                            onScaleDown: { scaleSelectedRegion(scale: 1.0 / scaleStep) },
                            onDelete: deleteSelectedRegion,
                            onEnableDrag: { setCanvasMode(.drag) }
                        )
                        .disabled(viewModel.isExporting)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    ZStack {
                        GeometryReader { geometry in
                            imageCanvas(image: image, geometry: geometry)
                        }

                        if canvasMode == .zoom && (canvasScale != 1.0 || canvasOffset != .zero) {
                            resetZoomButton
                        }
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hasRedactionRegions)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isScaleBarVisible)
            } else {
                EditorErrorView()
            }
        }
    }

    private var resetZoomButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        canvasScale = 1.0
                        lastCanvasScale = 1.0
                        canvasOffset = .zero
                        lastCanvasOffset = .zero
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.4)).frame(width: 44, height: 44))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(NSLocalizedString("action.resetZoom", comment: ""))
                .padding(.trailing, 12)
                .padding(.top, 12)
            }
            Spacer()
        }
    }

    // MARK: - Bottom Toolbar

    @ViewBuilder
    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            // PDF页面导航栏
            if viewModel.isPDFFile && viewModel.totalPDFPages > 1 {
                PDFPageNavigator(
                    currentPage: viewModel.currentPDFPageIndex,
                    totalPages: viewModel.totalPDFPages,
                    onPrevious: { goToPDFPage(viewModel.currentPDFPageIndex - 1) },
                    onNext: { goToPDFPage(viewModel.currentPDFPageIndex + 1) }
                )
                .disabled(viewModel.isExporting)
                Divider()
            }

            // 检测结果条
            if !viewModel.detectedRegions.isEmpty {
                DetectionResultBar(
                    regions: viewModel.regionsForCurrentPage,
                    otherPagesCount: viewModel.otherPagesRegionCount,
                    selectedIDs: selectedDetectedIDs,
                    onApply: applyDetectedRegion,
                    onIgnore: { region in
                        viewModel.detectedRegions.removeAll { $0.id == region.id }
                        selectedDetectedIDs.remove(region.id)
                    },
                    onApplyAll: applyAllDetectedRegions,
                    onDismiss: {
                        let currentPageIDs = Set(viewModel.regionsForCurrentPage.map { $0.id })
                        viewModel.detectedRegions.removeAll { currentPageIDs.contains($0.id) }
                        selectedDetectedIDs.subtract(currentPageIDs)
                    },
                    onSelect: toggleDetectedSelection,
                    onApplySelected: applySelectedDetectedRegions,
                    onIgnoreSelected: ignoreSelectedDetectedRegions
                )
                Divider()
            }

            // 效果选择栏
            EffectSelectorView(
                selectedEffect: $selectedEffect,
                selectedBrushSize: $selectedBrushSize,
                isScaleBarVisible: $isScaleBarVisible,
                onRotate: rotateImage,
                isRotateDisabled: viewModel.currentImage == nil || viewModel.isPDFFile || viewModel.isExporting,
                isBrushSizeDisabled: canvasMode != .brush,
                hasRedactionRegions: hasRedactionRegions,
                onDetect: {
                    Task {
                        await viewModel.detectSensitiveRegions()
                        // 检测失败此前静默（errorMessage 只被导出路径读取），此处统一 toast 提示
                        if let message = viewModel.detectErrorMessage {
                            showToast(message: message, isSuccess: false)
                        }
                    }
                },
                isDetecting: viewModel.isDetecting,
                isDetectDisabled: viewModel.isDetecting || viewModel.currentImage == nil || viewModel.isExporting,
                detectProgress: viewModel.detectProgress
            )

            Divider()
                .padding(.vertical, 8)

            // 操作按钮栏
            actionButtonsBar
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Action Buttons Bar

    private var actionButtonsBar: some View {
        HStack(spacing: 12) {
            // 左侧按钮组
            HStack(spacing: 8) {
                canvasModeMenu
                    .disabled(viewModel.isExporting)

                ToolbarIconButton(icon: "arrow.uturn.backward") {
                    performUndo()
                }
                .disabled((brushStrokes.isEmpty && !viewModel.canUndo) || viewModel.isExporting)
                .accessibilityLabel(NSLocalizedString("action.undoStroke", comment: ""))

                ToolbarIconButton(icon: "arrow.uturn.forward") {
                    viewModel.redo()
                }
                .disabled(!viewModel.canRedo || viewModel.isExporting)
                .accessibilityLabel(NSLocalizedString("action.redoStroke", comment: ""))
            }

            Spacer()

            // 右侧按钮组
            HStack(spacing: 8) {
                ToolbarButton(
                    icon: "checkmark.circle.fill",
                    title: NSLocalizedString("action.applyRedaction", comment: ""),
                    tintColor: .green,
                    isProminent: true
                ) {
                    applyMosaic()
                }
                .disabled(brushStrokes.isEmpty || canvasMode != .brush || viewModel.isExporting)

                ToolbarButton(
                    icon: viewModel.isExporting ? nil : "square.and.arrow.up",
                    title: exportButtonTitle,
                    tintColor: .blue,
                    isLoading: viewModel.isExporting
                ) {
                    performExport()
                }
                .disabled(viewModel.isExporting)

                // 导出中提供显式取消（此前取消只能通过"放弃编辑"间接触发）
                if viewModel.isExporting {
                    ToolbarIconButton(icon: "xmark", tintColor: .red) {
                        exportTask?.cancel()
                    }
                    .accessibilityLabel(NSLocalizedString("common.cancel", comment: ""))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// 导出按钮标题：导出中显示百分比进度
    private var exportButtonTitle: String {
        if viewModel.isExporting, let progress = viewModel.exportProgress {
            return String(
                format: NSLocalizedString("export.progress.title", comment: ""),
                Int((progress * 100).rounded()))
        }
        return NSLocalizedString("editor.done", comment: "")
    }

    private var canvasModeMenu: some View {
        Menu {
            ForEach(CanvasMode.allCases, id: \.self) { mode in
                Button {
                    setCanvasMode(mode)
                } label: {
                    Label(mode.localizedName, systemImage: mode.icon)
                }
            }
        } label: {
            Image(systemName: canvasMode.icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canvasMode == .brush ? Color(.systemGray5) : Color.orange.opacity(0.15))
                )
                .foregroundColor(canvasMode == .brush ? .primary : .orange)
        }
        .accessibilityLabel(canvasMode.localizedName)
    }

    // MARK: - Navigation Toolbar

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(NSLocalizedString("editor.cancel", comment: "")) {
                if hasUnsavedWork {
                    showDiscardConfirm = true
                } else {
                    dismiss()
                }
            }
            .disabled(viewModel.isExporting)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            groupMenu
        }
    }

    private var groupMenu: some View {
        Menu {
            ForEach(viewModel.allGroups, id: \.id) { group in
                Button {
                    if !viewModel.moveToGroup(group) {
                        showToast(
                            message: NSLocalizedString("import.move.failed", comment: ""),
                            isSuccess: false)
                    }
                } label: {
                    Label {
                        Text(group.name ?? NSLocalizedString("group.unnamed", comment: ""))
                    } icon: {
                        Image(systemName: group.iconName ?? "folder.fill")
                    }
                }
                .disabled(group.id == viewModel.currentGroup?.id)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.currentGroup?.iconName ?? "folder.fill")
                Text(
                    viewModel.currentGroup?.name
                        ?? NSLocalizedString("group.default", comment: "")
                )
                .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.accentColor)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Toast Overlay

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toastMessage {
            ToastView(message: message, isSuccess: toastIsSuccess)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: toastMessage)
        }
    }

    private func showToast(message: String, isSuccess: Bool) {
        toastMessage = message
        toastIsSuccess = isSuccess

        Task {
            try? await Task.sleep(nanoseconds: toastDisplayDurationNanoseconds)
            await MainActor.run {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }

    // MARK: - Image Canvas

    private func imageCanvas(image: UIImage, geometry: GeometryProxy) -> some View {
        let displaySize = CoordinateConverter.calculateDisplaySize(
            for: image.size, in: geometry.size)

        return ZStack {
            // 原始图片
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: displaySize.width, height: displaySize.height)
                // 以图片实际渲染帧为准同步显示尺寸(布局变化如检测结果条弹出时也会触发),
                // 否则涂抹/手势的屏幕坐标换算会基于陈旧尺寸而整体偏移
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    imageSize = newSize
                }

            // 涂抹路径、检测框和注释边框
            // 用Canvas回调提供的真实画布尺寸换算(画布与图片同框),
            // 不依赖imageSize状态,布局变化瞬间也不会错位
            Canvas { context, canvasSize in
                let drawConverter = CoordinateConverter(
                    imageSize: canvasSize, viewModel: viewModel)
                drawDetectedRegionHighlights(context: context, converter: drawConverter)
                drawBrushStrokes(context: context)
                if canvasMode == .drag {
                    drawRedactionBorders(context: context, converter: drawConverter)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .contentShape(Rectangle())
            .gesture(
                paintOrDragGesture(displaySize: displaySize),
                including: canvasMode == .zoom ? .none : .all
            )
            .gesture(
                zoomPanGesture(),
                including: canvasMode == .zoom ? .all : .none
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(canvasScale, anchor: .center)
        .offset(canvasOffset)
    }

    // MARK: - Canvas Drawing

    private func drawDetectedRegionHighlights(context: GraphicsContext, converter: CoordinateConverter) {
        for region in viewModel.regionsForCurrentPage {
            guard let rect = converter.regionScreenRect(for: region) else { continue }
            let path = Path(roundedRect: rect, cornerRadius: 4)

            // 选中或闪烁中的区域：蓝色加粗描边，与 chip 选中态对应
            if selectedDetectedIDs.contains(region.id) || flashRegionID == region.id {
                context.fill(path, with: .color(.blue.opacity(0.22)))
                context.stroke(path, with: .color(.blue), lineWidth: 4)
            } else {
                context.fill(path, with: .color(.orange.opacity(0.18)))
                context.stroke(path, with: .color(.orange), lineWidth: 2)
            }
        }
    }

    private func drawBrushStrokes(context: GraphicsContext) {
        // 绘制已完成的涂抹（所见即所得：与applyMosaic相同的外接矩形）
        for stroke in brushStrokes {
            drawStrokePreview(context: context, points: stroke.points, opacity: 0.5)
        }

        // 绘制当前正在进行的涂抹
        if !currentStroke.isEmpty {
            drawStrokePreview(context: context, points: currentStroke, opacity: 0.35)
        }
    }

    private func drawStrokePreview(context: GraphicsContext, points: [CGPoint], opacity: Double) {
        guard !points.isEmpty else { return }

        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        let padding = brushWidth / 2

        let rect = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
        let path = Path(roundedRect: rect, cornerRadius: 4)

        switch selectedEffect {
        case .white:
            context.fill(path, with: .color(.white.opacity(min(opacity + 0.35, 0.95))))
            context.stroke(path, with: .color(.gray.opacity(0.8)), lineWidth: 1.5)
        case .black:
            context.fill(path, with: .color(.black.opacity(opacity + 0.25)))
        case .mosaic, .blur:
            context.fill(path, with: .color(selectedEffect.previewColor.opacity(opacity)))
            context.stroke(path, with: .color(selectedEffect.previewColor.opacity(0.8)), lineWidth: 1.5)
        }
    }

    private func drawRedactionBorders(context: GraphicsContext, converter: CoordinateConverter) {
        if viewModel.isPDFFile {
            let annotations = viewModel.getCurrentPageAnnotations()
            for (index, pdfBounds) in annotations {
                if let screenRect = converter.pdfRectToScreen(pdfBounds) {
                    drawRegionBorder(
                        context: context, rect: screenRect, index: index)
                }
            }
        } else if viewModel.isImageFile {
            let regions = viewModel.getImageRedactionRegions()
            for (index, imageBounds) in regions {
                if let screenRect = converter.imageRectToScreen(imageBounds) {
                    drawRegionBorder(
                        context: context, rect: screenRect, index: index)
                }
            }
        }
    }

    private func drawRegionBorder(context: GraphicsContext, rect: CGRect, index: Int) {
        var adjustedRect = rect
        if index == selectedAnnotationIndex {
            adjustedRect = rect.offsetBy(dx: currentDragOffset.width, dy: currentDragOffset.height)
        }

        let borderPath = Path(roundedRect: adjustedRect, cornerRadius: 4)
        let isSelected = index == selectedAnnotationIndex
        context.stroke(
            borderPath,
            with: .color(isSelected ? .blue : .green.opacity(0.6)),
            lineWidth: isSelected ? 3 : 2
        )
    }

    // MARK: - Canvas Gesture

    private func paintOrDragGesture(displaySize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleDragChanged(location: value.location, displaySize: displaySize)
            }
            .onEnded { _ in
                handleDragEnded()
            }
    }

    private func zoomPanGesture() -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    canvasScale = min(max(lastCanvasScale * value, minCanvasScale), maxCanvasScale)
                }
                .onEnded { _ in
                    lastCanvasScale = canvasScale
                },
            DragGesture()
                .onChanged { value in
                    canvasOffset = CGSize(
                        width: lastCanvasOffset.width + value.translation.width,
                        height: lastCanvasOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    lastCanvasOffset = canvasOffset
                }
        )
    }

    private func handleDragChanged(location: CGPoint, displaySize: CGSize) {
        guard
            location.x >= 0 && location.x <= displaySize.width
                && location.y >= 0 && location.y <= displaySize.height
        else { return }

        switch canvasMode {
        case .drag:
            handleDragModeChanged(location: location)
        case .brush:
            if currentStroke.isEmpty {
                paintGestureStart = location
            }
            currentStroke.append(location)
        case .zoom:
            break
        }
    }

    private func handleDragModeChanged(location: CGPoint) {
        if isDraggingRegion {
            currentDragOffset = CGSize(
                width: location.x - dragStartLocation.x,
                height: location.y - dragStartLocation.y
            )
        } else {
            var tappedIndex: Int? = nil
            if viewModel.isPDFFile {
                if let pdfPoint = coordinateConverter.screenToPDF(location) {
                    tappedIndex = viewModel.findAnnotation(at: pdfPoint)
                }
            } else if viewModel.isImageFile {
                if let imagePoint = coordinateConverter.screenToImage(location) {
                    tappedIndex = viewModel.findImageRedactionRegion(at: imagePoint)
                }
            }

            if let index = tappedIndex {
                selectedAnnotationIndex = index
                dragStartLocation = location
                currentDragOffset = .zero
                isDraggingRegion = true
            } else {
                selectedAnnotationIndex = nil
                currentDragOffset = .zero
            }
        }
    }

    private func handleDragEnded() {
        switch canvasMode {
        case .drag:
            applyDragOffset()
            currentDragOffset = .zero
            isDraggingRegion = false
        case .brush:
            let endPoint = currentStroke.last ?? paintGestureStart
            let movement = hypot(endPoint.x - paintGestureStart.x, endPoint.y - paintGestureStart.y)

            if !viewModel.detectedRegions.isEmpty, movement < 6,
                let hitRegion = detectedRegion(at: paintGestureStart)
            {
                applyDetectedRegion(hitRegion)
                currentStroke.removeAll()
            } else if !currentStroke.isEmpty {
                brushStrokes.append(BrushStroke(points: currentStroke))
                currentStroke = []
            }
        case .zoom:
            break
        }
    }

    private func detectedRegion(at location: CGPoint) -> SensitiveRegion? {
        for region in viewModel.regionsForCurrentPage.reversed() {
            if let rect = coordinateConverter.regionScreenRect(for: region), rect.contains(location) {
                return region
            }
        }
        return nil
    }

    private func applyDragOffset() {
        guard let index = selectedAnnotationIndex else { return }

        if viewModel.isPDFFile {
            if let pdfDelta = coordinateConverter.screenDragToPDFDelta(currentDragOffset) {
                viewModel.moveAnnotation(at: index, offset: pdfDelta)
            }
        } else if viewModel.isImageFile {
            if let imageDelta = coordinateConverter.screenDragToImageDelta(currentDragOffset) {
                viewModel.moveImageRedactionRegion(at: index, offset: imageDelta)
            }
        }
    }

    // MARK: - Actions

    private func setCanvasMode(_ mode: CanvasMode) {
        guard mode != canvasMode else { return }
        if canvasMode == .brush {
            autoApplyPendingStrokesIfNeeded()
        }
        canvasMode = mode
        selectedAnnotationIndex = nil
        currentDragOffset = .zero
    }

    /// 若存在未应用的涂抹，先自动应用，避免静默丢弃
    private func autoApplyPendingStrokesIfNeeded() {
        guard !brushStrokes.isEmpty else { return }
        applyMosaic()
        showToast(message: NSLocalizedString("editor.autoApplied", comment: ""), isSuccess: true)
    }

    private func performUndo() {
        if !brushStrokes.isEmpty {
            undoLastStroke()
        } else {
            viewModel.undo()
        }
    }

    private func undoLastStroke() {
        if !brushStrokes.isEmpty {
            brushStrokes.removeLast()
        }
    }

    private func scaleSelectedRegion(scale: CGFloat) {
        if let index = selectedAnnotationIndex {
            viewModel.scaleRedactionRegion(at: index, scale: scale)
        }
    }

    private func deleteSelectedRegion() {
        guard let index = selectedAnnotationIndex else { return }
        if viewModel.isPDFFile {
            viewModel.removePDFAnnotation(at: index)
        } else if viewModel.isImageFile {
            viewModel.removeImageRedactionRegion(at: index)
        }
        selectedAnnotationIndex = nil
    }

    private func goToPDFPage(_ pageIndex: Int) {
        autoApplyPendingStrokesIfNeeded()
        viewModel.goToPDFPage(pageIndex)
        currentStroke.removeAll()
        selectedAnnotationIndex = nil
        currentDragOffset = .zero
        isDraggingRegion = false
    }

    private func rotateImage() {
        guard let currentImage = viewModel.currentImage else { return }

        // 已有脱敏记录时旋转会清空全部遮盖（坐标系变化、无法撤销），先确认
        if viewModel.canUndo {
            showRotateConfirm = true
            return
        }
        performRotate(currentImage)
    }

    private func performRotate(_ currentImage: UIImage) {
        autoApplyPendingStrokesIfNeeded()
        currentStroke.removeAll()

        if let rotatedImage = currentImage.rotated(by: .pi / 2) {
            viewModel.rotateCurrentImage(to: rotatedImage)
            imageSize = .zero
        }
    }

    private func applyMosaic() {
        guard let originalImage = viewModel.currentImage else { return }
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scaleX = originalImage.size.width / imageSize.width
        let scaleY = originalImage.size.height / imageSize.height
        let effect = selectedEffect.redactionEffect
        let padding: CGFloat = brushWidth / 2

        var rects: [CGRect] = []
        rects.reserveCapacity(brushStrokes.count)

        for stroke in brushStrokes {
            guard !stroke.points.isEmpty else { continue }

            let xs = stroke.points.map { $0.x }
            let ys = stroke.points.map { $0.y }
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0

            let rect: CGRect
            if viewModel.isPDFFile {
                rect = calculatePDFRect(
                    minX: minX, minY: minY, maxX: maxX, maxY: maxY, padding: padding)
            } else {
                rect = CGRect(
                    x: (minX - padding) * scaleX,
                    y: (minY - padding) * scaleY,
                    width: (maxX - minX + padding * 2) * scaleX,
                    height: (maxY - minY + padding * 2) * scaleY
                )
            }
            rects.append(rect)
        }

        // 批量应用：单快照 + 单次合成渲染（逐笔整图重绘曾致大图卡顿数秒）
        viewModel.selectedEffect = effect
        viewModel.applyRedactions(at: rects, effect: effect)

        brushStrokes.removeAll()

        if viewModel.isPDFFile {
            viewModel.refreshPDFPageImage()
        }
    }

    private func calculatePDFRect(
        minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat, padding: CGFloat
    ) -> CGRect {
        guard let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return .zero
        }

        let pageRect = page.bounds(for: .mediaBox)
        let pdfPageWidth = pageRect.width
        let pdfPageHeight = pageRect.height

        let pdfScaleX = pdfPageWidth / imageSize.width
        let pdfScaleY = pdfPageHeight / imageSize.height

        let pdfX = (minX - padding) * pdfScaleX
        let pdfY = (minY - padding) * pdfScaleY
        let pdfWidth = (maxX - minX + padding * 2) * pdfScaleX
        let pdfHeight = (maxY - minY + padding * 2) * pdfScaleY

        let flippedY = pdfPageHeight - pdfY - pdfHeight

        return CGRect(x: pdfX, y: flippedY, width: pdfWidth, height: pdfHeight)
    }

    // MARK: - Detection Actions

    private func applyDetectedRegion(_ region: SensitiveRegion) {
        // 校验区域所属页与当前页一致，避免跨页误应用
        if viewModel.isPDFFile, region.pageIndex != viewModel.currentPDFPageIndex {
            return
        }

        guard let rect = coordinateConverter.regionRect(for: region) else { return }

        viewModel.selectedEffect = selectedEffect.redactionEffect
        viewModel.applyRedaction(at: rect, effect: selectedEffect.redactionEffect)
        viewModel.detectedRegions.removeAll { $0.id == region.id }
        selectedDetectedIDs.remove(region.id)

        if viewModel.isPDFFile {
            viewModel.refreshPDFPageImage()
        }
    }

    private func applyAllDetectedRegions() {
        // 仅应用当前页的检测区域，其他页保留待处理
        let regions = viewModel.regionsForCurrentPage
        let effect = selectedEffect.redactionEffect

        // 批量应用：单快照 + 单次渲染
        let rects: [CGRect] = regions.compactMap { coordinateConverter.regionRect(for: $0) }
        viewModel.selectedEffect = effect
        viewModel.applyRedactions(at: rects, effect: effect)

        let appliedIDs = Set(regions.map { $0.id })
        viewModel.detectedRegions.removeAll { appliedIDs.contains($0.id) }
        selectedDetectedIDs.subtract(appliedIDs)

        if viewModel.isPDFFile {
            viewModel.refreshPDFPageImage()
        }
    }

    /// 点 chip 切换选中并闪烁对应框（图上定位）
    private func toggleDetectedSelection(_ region: SensitiveRegion) {
        if selectedDetectedIDs.contains(region.id) {
            selectedDetectedIDs.remove(region.id)
        } else {
            selectedDetectedIDs.insert(region.id)
        }
        // 短暂高亮定位：2 秒后恢复普通橙色框
        flashRegionID = region.id
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if flashRegionID == region.id {
                    flashRegionID = nil
                }
            }
        }
    }

    /// 应用所选区域（批量：单快照 + 单次渲染）
    private func applySelectedDetectedRegions() {
        let regions = viewModel.regionsForCurrentPage.filter { selectedDetectedIDs.contains($0.id) }
        guard !regions.isEmpty else { return }

        let effect = selectedEffect.redactionEffect
        let rects: [CGRect] = regions.compactMap { coordinateConverter.regionRect(for: $0) }
        viewModel.selectedEffect = effect
        viewModel.applyRedactions(at: rects, effect: effect)

        let appliedIDs = Set(regions.map { $0.id })
        viewModel.detectedRegions.removeAll { appliedIDs.contains($0.id) }
        selectedDetectedIDs.subtract(appliedIDs)

        if viewModel.isPDFFile {
            viewModel.refreshPDFPageImage()
        }
    }

    /// 忽略所选区域
    private func ignoreSelectedDetectedRegions() {
        viewModel.detectedRegions.removeAll { selectedDetectedIDs.contains($0.id) }
        selectedDetectedIDs.removeAll()
    }

    // MARK: - Export

    private func performExport() {
        guard !viewModel.isExporting else { return }

        exportTask = Task {
            if !brushStrokes.isEmpty {
                applyMosaic()
            }

            let success = await viewModel.exportFile()

            // 已被放弃/取消：不展示提示，不关闭编辑器，isExporting已由exportFile内部复位
            guard !Task.isCancelled else {
                await MainActor.run { exportTask = nil }
                return
            }

            await MainActor.run {
                if success {
                    var message = NSLocalizedString("export.success.detail", comment: "")
                    if let warning = viewModel.exportWarning {
                        message = warning + "\n" + message
                    }
                    showToast(message: message, isSuccess: true)
                } else if !viewModel.showUsageLimitAlert {
                    // 配额超限已通过alert提示，其余失败原因展示错误Toast且保留编辑内容
                    let message =
                        viewModel.errorMessage ?? NSLocalizedString("export.failed", comment: "")
                    showToast(message: message, isSuccess: false)
                }
                exportTask = nil
            }

            if success {
                // 成功后短暂展示提示，再弹出系统分享 sheet（存储/发送），
                // 分享 sheet 收起后关闭编辑器
                try? await Task.sleep(nanoseconds: toastDisplayDurationNanoseconds)
                await MainActor.run {
                    showShareSheet = true
                }
            }
        }
    }
}
