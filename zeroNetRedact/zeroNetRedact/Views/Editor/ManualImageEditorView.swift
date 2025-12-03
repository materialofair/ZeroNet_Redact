//
//  ManualImageEditorView.swift
//  ZeroNet Redact
//
//  手动图片编辑器 - 集成绘制功能和自动检测
//

import SwiftUI

/// 手动图片编辑器视图（完整功能版）
struct ManualImageEditorView: View {
    let file: RedactableFile
    @StateObject private var viewModel: EditorViewModel
    @StateObject private var drawingTool = ManualDrawingTool()
    @State private var showEffectPicker = false
    @State private var showToolbar = true
    @State private var imageSize: CGSize = .zero
    @Environment(\.dismiss) private var dismiss

    init(file: RedactableFile) {
        self.file = file
        _viewModel = StateObject(wrappedValue: EditorViewModel(file: file))
    }

    var body: some View {
        NavigationView {
            ZStack {
                // 主编辑区域
                mainEditingArea

                // 工具栏（可隐藏）
                VStack {
                    Spacer()

                    if showToolbar {
                        DrawingToolbar(
                            drawingTool: drawingTool,
                            showEffectPicker: $showEffectPicker
                        )
                        .padding()
                        .transition(.move(edge: .bottom))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("editor.imageRedact", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // AI自动检测
                        Button {
                            Task {
                                await viewModel.detectSensitiveRegions()
                            }
                        } label: {
                            Label(
                                NSLocalizedString("editor.aiDetect", comment: ""),
                                systemImage: "wand.and.stars")
                        }
                        .disabled(viewModel.isDetecting)

                        Divider()

                        // 应用绘制
                        Button {
                            applyDrawnRegions()
                        } label: {
                            Label(
                                NSLocalizedString("editor.applyRedact", comment: ""),
                                systemImage: "checkmark.circle")
                        }
                        .disabled(drawingTool.drawnRegions.isEmpty)

                        // 导出
                        Button {
                            Task {
                                await exportImage()
                            }
                        } label: {
                            Label(
                                NSLocalizedString("editor.export", comment: ""),
                                systemImage: "square.and.arrow.up")
                        }

                        Divider()

                        // 切换工具栏
                        Button {
                            withAnimation {
                                showToolbar.toggle()
                            }
                        } label: {
                            Label(
                                showToolbar
                                    ? NSLocalizedString("editor.hideToolbar", comment: "")
                                    : NSLocalizedString("editor.showToolbar", comment: ""),
                                systemImage: showToolbar ? "eye.slash" : "eye"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                await viewModel.loadFile()
            }
            .sheet(isPresented: $showEffectPicker) {
                EffectPickerSheet(
                    drawingTool: drawingTool,
                    isPresented: $showEffectPicker
                )
            }
        }
    }

    // MARK: - Main Editing Area

    private var mainEditingArea: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.black.opacity(0.05)
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView(NSLocalizedString("common.loading", comment: ""))
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if let image = viewModel.currentImage {
                    imageEditorCanvas(image: image, geometry: geometry)
                }
            }
        }
    }

    // MARK: - Image Editor Canvas

    private func imageEditorCanvas(image: UIImage, geometry: GeometryProxy) -> some View {
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

            // AI检测到的区域（红色框）
            ForEach(viewModel.detectedRegions) { region in
                detectedRegionOverlay(region: region, imageSize: displaySize)
            }

            // 手动绘制画布
            DrawingCanvasView(
                drawingTool: drawingTool,
                imageSize: displaySize
            )
            .frame(width: displaySize.width, height: displaySize.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detected Region Overlay

    private func detectedRegionOverlay(region: SensitiveRegion, imageSize: CGSize) -> some View {
        let convertedRect = convertVisionRectToUIKit(region.boundingBox, imageSize: imageSize)

        return Rectangle()
            .stroke(Color.red, lineWidth: 2)
            .background(Color.red.opacity(0.15))
            .frame(
                width: convertedRect.width,
                height: convertedRect.height
            )
            .position(
                x: convertedRect.midX,
                y: convertedRect.midY
            )
            .overlay(
                Text(region.type.displayName)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.red)
                    .cornerRadius(4)
                    .position(
                        x: convertedRect.midX,
                        y: convertedRect.minY - 12
                    ),
                alignment: .top
            )
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Actions

    private func applyDrawnRegions() {
        // 将绘制区域转换为图片坐标系
        let scaledRegions = drawingTool.drawnRegions.map { region in
            convertDrawnRegionToImageCoordinates(region)
        }

        viewModel.applyDrawnRegions(scaledRegions)
        drawingTool.clearAll()
    }

    private func exportImage() async {
        await viewModel.exportFile()

        if viewModel.errorMessage == nil {
            // 导出成功，关闭编辑器
            dismiss()
        }
    }

    // MARK: - Coordinate Conversion

    /// 计算图片在屏幕上的显示尺寸
    private func calculateDisplaySize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            // 图片更宽，以宽度为准
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // 图片更高，以高度为准
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    /// 将Vision坐标转换为UIKit坐标
    private func convertVisionRectToUIKit(_ visionRect: CGRect, imageSize: CGSize) -> CGRect {
        let imageWidth = imageSize.width
        let imageHeight = imageSize.height

        var rect = visionRect

        // 1. X坐标转换
        rect.origin.x *= imageWidth

        // 2. Y轴翻转
        rect.origin.y = (1 - rect.maxY) * imageHeight

        // 3. 尺寸转换
        rect.size.width *= imageWidth
        rect.size.height *= imageHeight

        return rect
    }

    /// 将绘制区域坐标转换为图片原始坐标
    private func convertDrawnRegionToImageCoordinates(_ region: DrawnRegion) -> DrawnRegion {
        guard let originalImage = viewModel.currentImage else { return region }

        let displaySize = imageSize
        let originalSize = originalImage.size

        // 计算缩放比例
        let scaleX = originalSize.width / displaySize.width
        let scaleY = originalSize.height / displaySize.height

        // 转换点坐标
        let scaledPoints = region.points.map { point in
            CGPoint(
                x: point.x * scaleX,
                y: point.y * scaleY
            )
        }

        return DrawnRegion(
            type: region.type,
            points: scaledPoints,
            effect: region.effect
        )
    }
}

// MARK: - Preview
// Preview需要CoreData环境，暂时禁用
// #Preview("手动图片编辑器") {
//     ManualImageEditorView(file: OriginalImage())
// }
