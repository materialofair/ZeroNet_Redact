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
    @State private var brushStrokes: [BrushStroke] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var imageSize: CGSize = .zero
    @State private var selectedEffect: BrushEffect = .black
    @State private var isInitialLoad = true

    // MARK: - Drag Annotation State
    @State private var isDragMode: Bool = false
    @State private var selectedAnnotationIndex: Int? = nil
    @State private var dragStartLocation: CGPoint = .zero
    @State private var currentDragOffset: CGSize = .zero
    @State private var isDraggingRegion: Bool = false

    // MARK: - Export State
    @State private var isExporting: Bool = false
    @State private var showExportToast: Bool = false
    @State private var exportSuccess: Bool = false

    // MARK: - UI State
    @State private var isScaleBarVisible: Bool = true

    // MARK: - Constants
    private let scaleStep: CGFloat = 1.1
    private let brushWidth: CGFloat = 40

    // MARK: - Computed Properties

    private var hasRedactionRegions: Bool {
        if viewModel.isPDFFile {
            return viewModel.getPDFAnnotationCount() > 0
        } else if viewModel.isImageFile {
            return !viewModel.getImageRedactionRegions().isEmpty
        }
        return false
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
        NavigationView {
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
        .navigationViewStyle(.stack)
        .accentColor(.blue)
        .overlay(alignment: .top) { toastOverlay }
    }

    // MARK: - Editor Content

    @ViewBuilder
    private var editorContent: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                Color.black.opacity(0.05)

                if isInitialLoad || viewModel.isLoading {
                    EditorLoadingView()
                } else if let image = viewModel.currentImage {
                    ZStack(alignment: .leading) {
                        imageCanvas(image: image, geometry: geometry)

                        if hasRedactionRegions && isScaleBarVisible {
                            ScaleControlBar(
                                isDragMode: isDragMode,
                                hasSelection: selectedAnnotationIndex != nil,
                                onScaleUp: { scaleSelectedRegion(scale: scaleStep) },
                                onScaleDown: { scaleSelectedRegion(scale: 1.0 / scaleStep) },
                                onDelete: deleteSelectedRegion
                            )
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: hasRedactionRegions)
                    .animation(.easeInOut(duration: 0.2), value: isScaleBarVisible)
                } else {
                    EditorErrorView()
                }
            }
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
                Divider()
            }

            // 效果选择栏
            EffectSelectorView(
                selectedEffect: $selectedEffect,
                isScaleBarVisible: $isScaleBarVisible,
                onRotate: rotateImage,
                isRotateDisabled: viewModel.currentImage == nil || viewModel.isPDFFile,
                hasRedactionRegions: hasRedactionRegions
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
                ToolbarButton(
                    icon: isDragMode ? "hand.draw.fill" : "hand.point.up.left.fill",
                    title: NSLocalizedString(isDragMode ? "mode.brush" : "mode.drag", comment: ""),
                    tintColor: isDragMode ? .orange : .blue
                ) {
                    toggleDragMode()
                }

                ToolbarIconButton(icon: "arrow.uturn.backward") {
                    undoLastStroke()
                }
                .disabled(brushStrokes.isEmpty || isDragMode)

                ToolbarIconButton(icon: "arrow.uturn.backward.circle") {
                    viewModel.undo()
                }
                .disabled(!viewModel.canUndo)
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
                .disabled(brushStrokes.isEmpty || isDragMode)

                ToolbarButton(
                    icon: isExporting ? nil : "square.and.arrow.up",
                    title: NSLocalizedString("editor.done", comment: ""),
                    tintColor: .blue,
                    isLoading: isExporting
                ) {
                    performExport()
                }
                .disabled(isExporting)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Navigation Toolbar

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(NSLocalizedString("editor.cancel", comment: "")) {
                dismiss()
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            groupMenu
        }
    }

    private var groupMenu: some View {
        Menu {
            ForEach(viewModel.allGroups, id: \.id) { group in
                Button {
                    viewModel.moveToGroup(group)
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
        if showExportToast {
            ToastView(
                message: NSLocalizedString("export.success", comment: "导出成功"),
                isSuccess: exportSuccess
            )
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: showExportToast)
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
                .onAppear { imageSize = displaySize }
                .onChange(of: image.size) { imageSize = displaySize }

            // 涂抹路径和注释边框
            Canvas { context, _ in
                drawBrushStrokes(context: context)
                if isDragMode {
                    drawRedactionBorders(context: context)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .contentShape(Rectangle())
            .gesture(canvasGesture(displaySize: displaySize))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Canvas Drawing

    private func drawBrushStrokes(context: GraphicsContext) {
        // 绘制已完成的涂抹
        for stroke in brushStrokes {
            drawStroke(context: context, points: stroke.points, opacity: 0.6)
        }

        // 绘制当前正在进行的涂抹
        if !currentStroke.isEmpty {
            drawStroke(context: context, points: currentStroke, opacity: 0.4)
        }
    }

    private func drawStroke(context: GraphicsContext, points: [CGPoint], opacity: Double) {
        var path = Path()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        context.stroke(path, with: .color(.red.opacity(opacity)), lineWidth: brushWidth)
    }

    private func drawRedactionBorders(context: GraphicsContext) {
        if viewModel.isPDFFile {
            let annotations = viewModel.getCurrentPageAnnotations()
            for (index, pdfBounds) in annotations {
                if let screenRect = coordinateConverter.pdfRectToScreen(pdfBounds) {
                    drawRegionBorder(
                        context: context, rect: screenRect, index: index)
                }
            }
        } else if viewModel.isImageFile {
            let regions = viewModel.getImageRedactionRegions()
            for (index, imageBounds) in regions {
                if let screenRect = coordinateConverter.imageRectToScreen(imageBounds) {
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

    private func canvasGesture(displaySize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleDragChanged(location: value.location, displaySize: displaySize)
            }
            .onEnded { _ in
                handleDragEnded()
            }
    }

    private func handleDragChanged(location: CGPoint, displaySize: CGSize) {
        guard
            location.x >= 0 && location.x <= displaySize.width
                && location.y >= 0 && location.y <= displaySize.height
        else { return }

        if isDragMode {
            handleDragModeChanged(location: location)
        } else {
            currentStroke.append(location)
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
        if isDragMode {
            applyDragOffset()
            currentDragOffset = .zero
            isDraggingRegion = false
        } else {
            if !currentStroke.isEmpty {
                brushStrokes.append(BrushStroke(points: currentStroke))
                currentStroke = []
            }
        }
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

    private func toggleDragMode() {
        isDragMode.toggle()
        selectedAnnotationIndex = nil
        currentDragOffset = .zero
        if isDragMode {
            brushStrokes.removeAll()
            currentStroke.removeAll()
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
        viewModel.goToPDFPage(pageIndex)
        brushStrokes.removeAll()
        currentStroke.removeAll()
    }

    private func rotateImage() {
        guard let currentImage = viewModel.currentImage else { return }

        brushStrokes.removeAll()
        currentStroke.removeAll()

        if let rotatedImage = currentImage.rotated(by: .pi / 2) {
            viewModel.rotateCurrentImage(to: rotatedImage)
            imageSize = .zero
        }
    }

    private func applyMosaic() {
        guard let originalImage = viewModel.currentImage else { return }

        let scaleX = originalImage.size.width / imageSize.width
        let scaleY = originalImage.size.height / imageSize.height
        let effect = selectedEffect.redactionEffect
        let padding: CGFloat = brushWidth / 2

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

            viewModel.selectedEffect = effect
            viewModel.applyRedaction(at: rect)
        }

        brushStrokes.removeAll()

        if viewModel.isPDFFile {
            if let renderedImage = viewModel.renderCurrentPDFPage() {
                viewModel.currentImage = renderedImage
            }
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

    private func performExport() {
        guard !isExporting else { return }

        isExporting = true

        Task {
            if !brushStrokes.isEmpty {
                applyMosaic()
            }

            await viewModel.exportFile()

            await MainActor.run {
                isExporting = false
                exportSuccess = true
                showExportToast = true
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)

            await MainActor.run {
                showExportToast = false
                dismiss()
            }
        }
    }
}
