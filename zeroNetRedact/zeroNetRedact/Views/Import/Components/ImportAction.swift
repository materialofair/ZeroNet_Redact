//
//  ImportAction.swift
//  ZeroNet Redact
//
//  导入动作的统一定义：空状态引导卡片与悬浮「+」菜单共用同一数据源，
//  图标、文案、颜色与功能开关门控只在此维护一份
//

import SwiftUI

/// 可用的导入动作（图片/视频/PDF/拼接长图）
enum ImportAction: CaseIterable, Identifiable {
    case photos
    case video
    case pdf
    case stitch

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .photos: return "import.selectPhotos"
        case .video: return "import.selectVideo"
        case .pdf: return "import.selectPDF"
        case .stitch: return "stitch.button"
        }
    }

    var icon: String {
        switch self {
        case .photos: return "photo.on.rectangle.angled"
        case .video: return "video.fill"
        case .pdf: return "doc.text.fill"
        case .stitch: return "rectangle.stack.badge.plus"
        }
    }

    var iconColor: Color {
        switch self {
        case .photos: return DesignSystem.Colors.primaryBlue
        case .video: return DesignSystem.Colors.successGreen
        case .pdf: return DesignSystem.Colors.warningOrange
        case .stitch: return DesignSystem.Colors.primaryPurple
        }
    }

    /// 单次选择上限提示只跟图片按钮关联（该上限不适用于 PDF）
    var captionKey: String? {
        self == .photos ? "import.maxSelection" : nil
    }

    /// 是否出现在入口列表（拼接长图暂缓发布，由功能开关控制）
    var isAvailable: Bool {
        self != .stitch || FeatureFlags.stitchEnabled
    }

    var displayName: String {
        NSLocalizedString(titleKey, comment: "")
    }

    var caption: String? {
        captionKey.map { NSLocalizedString($0, comment: "") }
    }

    /// 当前功能开关下可展示的入口动作
    static var availableActions: [ImportAction] {
        allCases.filter(\.isAvailable)
    }
}
