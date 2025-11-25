//
//  DrawingCanvasView.swift
//  ZeroNet Redact
//
//  绘制画布 - 处理用户手势，支持涂抹和框选
//

import SwiftUI

/// 绘制画布视图
struct DrawingCanvasView: View {
    @ObservedObject var drawingTool: ManualDrawingTool
    let imageSize: CGSize

    var body: some View {
        ZStack {
            // 已绘制的区域
            ForEach(drawingTool.drawnRegions) { region in
                drawRegion(region)
            }

            // 当前正在绘制的区域
            if drawingTool.isDrawing {
                drawCurrentPath()
            }
        }
        .contentShape(Rectangle())  // 确保整个区域可点击
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
    }

    // MARK: - Drawing Methods

    /// 绘制已完成的区域
    @ViewBuilder
    private func drawRegion(_ region: DrawnRegion) -> some View {
        switch region.type {
        case .freehand:
            // 自由涂抹：绘制路径
            Path { path in
                guard let firstPoint = region.points.first else { return }
                path.move(to: firstPoint)
                for point in region.points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(effectColor(for: region.effect), lineWidth: 30)
            .opacity(0.7)

        case .rectangle:
            // 矩形框选
            Rectangle()
                .fill(effectColor(for: region.effect))
                .opacity(0.5)
                .frame(width: region.boundingRect.width, height: region.boundingRect.height)
                .position(x: region.boundingRect.midX, y: region.boundingRect.midY)
                .overlay(
                    Rectangle()
                        .stroke(effectColor(for: region.effect), lineWidth: 2)
                        .frame(width: region.boundingRect.width, height: region.boundingRect.height)
                        .position(x: region.boundingRect.midX, y: region.boundingRect.midY)
                )
        }
    }

    /// 绘制当前正在进行的路径
    @ViewBuilder
    private func drawCurrentPath() -> some View {
        switch drawingTool.currentMode {
        case .freehand:
            // 自由涂抹：实时显示路径
            if !drawingTool.currentPath.isEmpty {
                Path { path in
                    guard let firstPoint = drawingTool.currentPath.first else { return }
                    path.move(to: firstPoint)
                    for point in drawingTool.currentPath.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(effectColor(for: drawingTool.currentEffect), lineWidth: 30)
                .opacity(0.5)
            }

        case .rectangle:
            // 矩形框选：显示实时预览框
            if let previewRect = drawingTool.currentPreviewRect {
                Rectangle()
                    .stroke(effectColor(for: drawingTool.currentEffect), lineWidth: 2)
                    .fill(effectColor(for: drawingTool.currentEffect).opacity(0.2))
                    .frame(width: previewRect.width, height: previewRect.height)
                    .position(x: previewRect.midX, y: previewRect.midY)
            }
        }
    }

    // MARK: - Gesture Handlers

    private func handleDragChanged(_ value: DragGesture.Value) {
        let location = value.location

        // 检查是否在图片范围内
        guard
            location.x >= 0 && location.x <= imageSize.width && location.y >= 0
                && location.y <= imageSize.height
        else {
            return
        }

        if !drawingTool.isDrawing {
            drawingTool.startDrawing(at: location)
        } else {
            drawingTool.addPoint(location)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        drawingTool.finishDrawing()
    }

    // MARK: - Helper Methods

    /// 根据脱敏效果获取对应的颜色
    private func effectColor(for effect: RedactionEffect) -> Color {
        switch effect {
        case .mosaic:
            return .gray
        case .blur:
            return .blue
        case .rectangle(let color, _):
            return Color(color)
        case .solidBlack:
            return .black
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var drawingTool = ManualDrawingTool()

        var body: some View {
            VStack {
                ZStack {
                    Color.gray.opacity(0.2)

                    DrawingCanvasView(
                        drawingTool: drawingTool,
                        imageSize: CGSize(width: 300, height: 400)
                    )
                }
                .frame(width: 300, height: 400)
                .border(Color.blue)

                HStack {
                    Button("矩形") {
                        drawingTool.currentMode = .rectangle
                    }
                    .buttonStyle(.bordered)

                    Button("涂抹") {
                        drawingTool.currentMode = .freehand
                    }
                    .buttonStyle(.bordered)

                    Button("撤销") {
                        drawingTool.undoLast()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!drawingTool.canUndo)

                    Button("清空") {
                        drawingTool.clearAll()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
    }

    return PreviewWrapper()
}
