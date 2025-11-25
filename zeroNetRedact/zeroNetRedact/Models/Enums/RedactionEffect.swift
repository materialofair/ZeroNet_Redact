//
//  RedactionEffect.swift
//  ZeroNet Redact
//
//  脱敏效果类型枚举
//

import UIKit

/// 脱敏效果类型
enum RedactionEffect: Equatable, Hashable {
    case mosaic(pixelSize: Int)  // 马赛克（像素大小）
    case blur(radius: Float)  // 模糊（模糊半径）
    case rectangle(color: UIColor, opacity: Float)  // 矩形遮盖（颜色+透明度）
    case solidBlack  // 纯黑遮盖

    // 实现Hashable
    func hash(into hasher: inout Hasher) {
        switch self {
        case .mosaic(let pixelSize):
            hasher.combine("mosaic")
            hasher.combine(pixelSize)
        case .blur(let radius):
            hasher.combine("blur")
            hasher.combine(radius)
        case .rectangle(let color, let opacity):
            hasher.combine("rectangle")
            if let components = color.cgColor.components {
                hasher.combine(components)
            }
            hasher.combine(opacity)
        case .solidBlack:
            hasher.combine("solidBlack")
        }
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case .mosaic: return "马赛克"
        case .blur: return "模糊"
        case .rectangle: return "矩形遮盖"
        case .solidBlack: return "纯黑遮盖"
        }
    }

    /// 图标
    var icon: String {
        switch self {
        case .mosaic: return "square.grid.3x3"
        case .blur: return "circle.dotted"
        case .rectangle: return "rectangle.fill"
        case .solidBlack: return "square.fill"
        }
    }

    /// 默认效果
    static var `default`: RedactionEffect {
        return .solidBlack
    }
}
