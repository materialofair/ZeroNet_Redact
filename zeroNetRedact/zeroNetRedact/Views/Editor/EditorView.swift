import SwiftUI

struct EditorView: View {
    let file: RedactableFile
    @StateObject private var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(file: RedactableFile) {
        self.file = file
        _viewModel = StateObject(wrappedValue: EditorViewModel(file: file))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 工具栏
                EditorToolbar(viewModel: viewModel)
                    .padding()
                    .background(Color(.systemBackground))

                Divider()

                // 编辑区域
                ZStack {
                    Color.black.opacity(0.05)
                        .ignoresSafeArea()

                    if viewModel.isLoading {
                        ProgressView("加载中...")
                    } else if let error = viewModel.errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // 根据文件类型显示不同编辑器
                        if file.fileType == .image {
                            ImageEditorCanvas(viewModel: viewModel)
                        } else {
                            PDFEditorCanvas(viewModel: viewModel)
                        }
                    }
                }

                Divider()

                // 底部操作栏
                EditorBottomBar(viewModel: viewModel, dismiss: dismiss)
                    .padding()
                    .background(Color(.systemBackground))
            }
            .navigationTitle("编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadFile()
            }
            .sheet(isPresented: $viewModel.showGroupPicker) {
                GroupPickerSheet(viewModel: viewModel)
            }
        }
    }
}

struct EditorToolbar: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        HStack {
            // AI检测按钮
            Button(action: {
                Task {
                    await viewModel.detectSensitiveRegions()
                }
            }) {
                Label("AI检测", systemImage: "wand.and.stars")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isDetecting)

            Spacer()

            // 分组选择按钮
            Button(action: {
                viewModel.showGroupPicker = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.currentGroup?.iconName ?? "folder.fill")
                        .font(.caption)
                    Text(viewModel.currentGroup?.name ?? "默认分组")
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }

            Spacer()

            // 涂抹效果选择
            Menu {
                ForEach(
                    [
                        RedactionEffect.solidBlack, .mosaic(pixelSize: 20), .blur(radius: 10.0),
                        .rectangle(color: .black, opacity: 0.8),
                    ], id: \.self
                ) { effect in
                    Button(action: {
                        viewModel.selectedEffect = effect
                    }) {
                        Label(effect.displayName, systemImage: "checkmark")
                    }
                }
            } label: {
                Label("效果", systemImage: "paintbrush")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            // 撤销/重做
            HStack(spacing: 8) {
                Button(action: {
                    viewModel.undo()
                }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)

                Button(action: {
                    viewModel.redo()
                }) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
            }
        }
    }
}

struct EditorBottomBar: View {
    @ObservedObject var viewModel: EditorViewModel
    let dismiss: DismissAction

    var body: some View {
        HStack {
            // 检测到的敏感区域数量
            if !viewModel.detectedRegions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("检测到 \(viewModel.detectedRegions.count) 处敏感信息")
                        .font(.caption)
                }
            }

            Spacer()

            // 导出按钮
            Button(action: {
                Task {
                    await viewModel.exportFile()
                    dismiss()
                }
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("导出")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(viewModel.isExporting)
        }
    }
}

// MARK: - 检测区域视图
struct DetectedRegionView: View {
    let region: SensitiveRegion
    let imageSize: CGSize
    let onTap: () -> Void

    var body: some View {
        let convertedRect = convertVisionRectToUIKit(region.boundingBox, imageSize: imageSize)

        Rectangle()
            .stroke(Color.red, lineWidth: 3)
            .background(Color.red.opacity(0.25))
            .frame(
                width: convertedRect.width,
                height: convertedRect.height
            )
            .position(
                x: convertedRect.midX,
                y: convertedRect.midY
            )
            .overlay(
                // 添加信息标签
                VStack {
                    Text(region.type.displayName)
                        .font(.caption2)
                        .padding(4)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    Spacer()
                }
                .frame(width: convertedRect.width, height: convertedRect.height)
                .position(x: convertedRect.midX, y: convertedRect.minY - 15)
            )
            .onTapGesture(perform: onTap)
    }

    /// 将Vision框架的归一化坐标转换为UIKit像素坐标
    /// Vision坐标系: 原点在左下角, 归一化 (0-1)
    /// UIKit坐标系: 原点在左上角, 像素单位
    ///
    /// 参考Apple官方文档: https://developer.apple.com/documentation/vision/detecting_objects_in_still_images
    private func convertVisionRectToUIKit(_ visionRect: CGRect, imageSize: CGSize) -> CGRect {
        let imageWidth = imageSize.width
        let imageHeight = imageSize.height

        // Begin with input rect (normalized coordinates)
        var rect = visionRect

        // 1. Reposition origin (x坐标转换)
        rect.origin.x *= imageWidth

        // 2. Y轴翻转: Vision的Y坐标是从底部开始,UIKit从顶部开始
        // maxY是矩形的顶边(在Vision坐标系),需要翻转到UIKit坐标系
        rect.origin.y = (1 - rect.maxY) * imageHeight

        // 3. Rescale normalized size to pixel size
        rect.size.width *= imageWidth
        rect.size.height *= imageHeight

        // 🔍 Debug输出 - 帮助定位坐标转换问题
        print("🔄 坐标转换:")
        print(
            "   Vision归一化坐标: origin(\(visionRect.origin.x), \(visionRect.origin.y)) size(\(visionRect.size.width) x \(visionRect.size.height))"
        )
        print("   Vision maxY (顶边): \(visionRect.maxY)")
        print("   图片尺寸: \(imageWidth) x \(imageHeight)")
        print(
            "   UIKit像素坐标: origin(\(rect.origin.x), \(rect.origin.y)) size(\(rect.size.width) x \(rect.size.height))"
        )

        return rect
    }
}

// MARK: - 图片编辑画布
struct ImageEditorCanvas: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var currentRect: CGRect?
    @State private var imageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                imageView
                detectedRegionsView
                currentRectView
            }
            .gesture(drawingGesture)
        }
    }

    // MARK: - 子视图

    private var imageView: some View {
        Group {
            if let image = viewModel.currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(imageSizeReader)
            } else {
                ProgressView("加载中...")
            }
        }
    }

    private var imageSizeReader: some View {
        GeometryReader { imageGeometry in
            Color.clear.onAppear {
                imageSize = imageGeometry.size
            }
        }
    }

    private var detectedRegionsView: some View {
        ForEach(viewModel.detectedRegions) { region in
            DetectedRegionView(
                region: region,
                imageSize: imageSize,
                onTap: {
                    // 使用同样的转换方法
                    let convertedRect = convertVisionToUIKit(
                        region.boundingBox, imageSize: imageSize)
                    print("🎯 点击区域 - 原始: \(region.boundingBox), 转换后: \(convertedRect)")
                    viewModel.applyRedaction(at: convertedRect)
                }
            )
        }
    }

    /// 统一的Vision坐标转换方法
    private func convertVisionToUIKit(_ visionRect: CGRect, imageSize: CGSize) -> CGRect {
        var rect = visionRect

        // 1. X坐标和宽度缩放
        rect.origin.x *= imageSize.width
        rect.size.width *= imageSize.width

        // 2. Y坐标翻转 + 缩放
        rect.origin.y = (1 - rect.maxY) * imageSize.height
        rect.size.height *= imageSize.height

        return rect
    }

    @ViewBuilder
    private var currentRectView: some View {
        if let rect = currentRect {
            Rectangle()
                .stroke(Color.blue, lineWidth: 2)
                .background(Color.blue.opacity(0.3))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    // MARK: - 手势

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                updateCurrentRect(with: value)
            }
            .onEnded { _ in
                finishDrawing()
            }
    }

    private func updateCurrentRect(with value: DragGesture.Value) {
        let startPoint = value.startLocation
        let currentPoint = value.location

        let origin = CGPoint(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y)
        )
        let size = CGSize(
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )

        currentRect = CGRect(origin: origin, size: size)
    }

    private func finishDrawing() {
        if let rect = currentRect {
            viewModel.applyRedaction(at: rect)
        }
        currentRect = nil
    }
}

struct PDFEditorCanvas: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        Text("PDF编辑画布 - 待实现")
            .foregroundColor(.secondary)
    }
}
