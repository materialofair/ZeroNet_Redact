//
//  ManualDrawingTool.swift
//  ZeroNet Redact
//
//  手动绘制工具 - 支持自由涂抹和矩形框选
//

import Combine
import SwiftUI

/// 绘制模式
enum DrawingMode: String, CaseIterable {
    case freehand = "涂抹"
    case rectangle = "矩形"

    var icon: String {
        switch self {
        case .freehand: return "scribble"
        case .rectangle: return "rectangle.dashed"
        }
    }
}

/// 绘制的区域
struct DrawnRegion: Identifiable, Equatable {
    let id = UUID()
    let type: DrawingMode
    let points: [CGPoint]  // 自由路径的点，或矩形的两个角点
    let effect: RedactionEffect

    /// 获取边界矩形
    var boundingRect: CGRect {
        switch type {
        case .freehand:
            return calculateBoundingRect(of: points)
        case .rectangle:
            guard points.count >= 2 else { return .zero }
            let start = points[0]
            let end = points[1]
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        }
    }

    /// 计算路径的边界矩形（自由涂抹）
    private func calculateBoundingRect(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }

        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 0

        // 自由涂抹：添加一定的padding，确保完全覆盖
        let padding: CGFloat = 20

        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + padding * 2,
            height: (maxY - minY) + padding * 2
        )
    }

    static func == (lhs: DrawnRegion, rhs: DrawnRegion) -> Bool {
        lhs.id == rhs.id
    }
}

/// 手动绘制工具
class ManualDrawingTool: ObservableObject {

    // MARK: - Published Properties

    @Published var currentMode: DrawingMode = .rectangle
    @Published var currentEffect: RedactionEffect = .solidBlack
    @Published var currentPath: [CGPoint] = []
    @Published var drawnRegions: [DrawnRegion] = []
    @Published var isDrawing: Bool = false

    // MARK: - Public Methods

    /// 开始绘制
    func startDrawing(at point: CGPoint) {
        isDrawing = true
        currentPath = [point]
    }

    /// 添加点到当前路径
    func addPoint(_ point: CGPoint) {
        guard isDrawing else { return }

        switch currentMode {
        case .freehand:
            // 自由涂抹：添加所有点
            currentPath.append(point)

        case .rectangle:
            // 矩形框选：只保留起点和当前点
            if currentPath.count >= 2 {
                currentPath[1] = point
            } else {
                currentPath.append(point)
            }
        }
    }

    /// 完成当前绘制
    func finishDrawing() {
        guard isDrawing, !currentPath.isEmpty else {
            resetCurrentDrawing()
            return
        }

        // 验证绘制有效性
        switch currentMode {
        case .freehand:
            // 自由涂抹：至少需要2个点
            guard currentPath.count >= 2 else {
                resetCurrentDrawing()
                return
            }

        case .rectangle:
            // 矩形：需要2个点，且形成有效矩形
            guard currentPath.count >= 2 else {
                resetCurrentDrawing()
                return
            }

            let start = currentPath[0]
            let end = currentPath[1]
            let width = abs(end.x - start.x)
            let height = abs(end.y - start.y)

            // 矩形太小则忽略（防止误触）
            guard width > 10 && height > 10 else {
                resetCurrentDrawing()
                return
            }
        }

        // 创建绘制区域
        let region = DrawnRegion(
            type: currentMode,
            points: currentPath,
            effect: currentEffect
        )

        drawnRegions.append(region)
        resetCurrentDrawing()
    }

    /// 取消当前绘制
    func cancelDrawing() {
        resetCurrentDrawing()
    }

    /// 撤销最后一个绘制
    func undoLast() {
        guard !drawnRegions.isEmpty else { return }
        drawnRegions.removeLast()
    }

    /// 清空所有绘制
    func clearAll() {
        drawnRegions.removeAll()
        resetCurrentDrawing()
    }

    /// 删除指定区域
    func removeRegion(_ region: DrawnRegion) {
        drawnRegions.removeAll { $0.id == region.id }
    }

    // MARK: - Private Methods

    private func resetCurrentDrawing() {
        isDrawing = false
        currentPath.removeAll()
    }

    // MARK: - Computed Properties

    /// 是否可以撤销
    var canUndo: Bool {
        !drawnRegions.isEmpty
    }

    /// 当前绘制的预览矩形（实时显示）
    var currentPreviewRect: CGRect? {
        guard isDrawing, !currentPath.isEmpty else { return nil }

        switch currentMode {
        case .freehand:
            return nil  // 自由涂抹不显示预览矩形

        case .rectangle:
            guard currentPath.count >= 2 else { return nil }
            let start = currentPath[0]
            let end = currentPath[1]
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        }
    }
}
