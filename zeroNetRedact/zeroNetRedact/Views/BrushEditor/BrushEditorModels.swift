//
//  BrushEditorModels.swift
//  ZeroNet Redact
//
//  涂抹编辑器的数据模型和枚举定义
//

import SwiftUI

// MARK: - Brush Stroke Model

/// 涂抹路径
struct BrushStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
}

// MARK: - Brush Effect Enum

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

// MARK: - Canvas Mode Enum

/// 画布交互模式
enum CanvasMode: String, CaseIterable {
    case brush
    case drag
    case zoom

    var icon: String {
        switch self {
        case .brush: return "paintbrush.pointed.fill"
        case .drag: return "hand.point.up.left.fill"
        case .zoom: return "arrow.up.left.and.arrow.down.right.circle.fill"
        }
    }

    var localizedName: String {
        switch self {
        case .brush: return NSLocalizedString("mode.brush", comment: "")
        case .drag: return NSLocalizedString("mode.drag", comment: "")
        case .zoom: return NSLocalizedString("mode.zoom", comment: "")
        }
    }
}

// MARK: - Brush Size Enum

/// 画笔粗细
enum BrushSize: String, CaseIterable {
    case thin
    case medium
    case thick

    var width: CGFloat {
        switch self {
        case .thin: return 20
        case .medium: return 40
        case .thick: return 70
        }
    }

    var localizedName: String {
        switch self {
        case .thin: return NSLocalizedString("brush.size.thin", comment: "")
        case .medium: return NSLocalizedString("brush.size.medium", comment: "")
        case .thick: return NSLocalizedString("brush.size.thick", comment: "")
        }
    }
}

// MARK: - UIImage Rotation Extension

extension UIImage {
    /// 按指定弧度旋转图片
    func rotated(by radians: CGFloat) -> UIImage? {
        let newSize = CGSize(width: size.height, height: size.width)

        UIGraphicsBeginImageContextWithOptions(newSize, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // 移动原点到中心
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        // 旋转
        context.rotate(by: radians)
        // 绘制图片
        draw(
            in: CGRect(
                x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))

        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return rotatedImage
    }
}
