//
//  ImportActionTile.swift
//  ZeroNet Redact
//
//  首页导入操作卡片（空状态 + 底部操作栏共用，保证两处样式一致）
//

import SwiftUI

/// 等尺寸导入操作卡片：左侧彩色图标 + 右侧标题（可选副标题）
struct ImportActionTile: View {
    enum Style {
        /// 空状态 2x2 大卡片
        case regular
        /// 底部操作栏紧凑卡片
        case compact

        var iconSize: CGFloat {
            switch self {
            case .regular: return 44
            case .compact: return 34
            }
        }

        var iconFontSize: CGFloat {
            switch self {
            case .regular: return 20
            case .compact: return 16
            }
        }

        var iconCornerRadius: CGFloat {
            switch self {
            case .regular: return DesignSystem.CornerRadius.medium
            case .compact: return 10
            }
        }

        var minHeight: CGFloat {
            switch self {
            case .regular: return 84
            case .compact: return 52
            }
        }
    }

    let icon: String
    let title: String
    var caption: String?
    let iconColor: Color
    var style: Style = .regular
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // 图标圆角底色
                Image(systemName: icon)
                    .font(.system(size: style.iconFontSize, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: style.iconSize, height: style.iconSize)
                    .background(
                        RoundedRectangle(cornerRadius: style.iconCornerRadius, style: .continuous)
                            .fill(iconColor.opacity(colorScheme == .dark ? 0.24 : 0.12))
                    )

                // 标题 + 可选副标题
                // Dynamic Type:大字号下允许换行而非压缩(minimumScaleFactor 会缩小文字,移除)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(2)

                    if let caption, style == .regular {
                        Text(caption)
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, style == .regular ? DesignSystem.Spacing.md : 10)
            .frame(maxWidth: .infinity, minHeight: style.minHeight, alignment: .leading)
            .background(DesignSystem.Colors.backgroundCard)
            .cornerRadius(DesignSystem.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        }
        .buttonStyle(ImportActionTileButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(caption ?? "")
    }
}

/// 导入卡片按压反馈（Reduce Motion 时禁用缩放动画）
private struct ImportActionTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 预览

#Preview("Regular") {
    VStack(spacing: 12) {
        ImportActionTile(
            icon: "photo.on.rectangle.angled",
            title: NSLocalizedString("import.selectPhotos", comment: ""),
            caption: NSLocalizedString("import.maxSelection", comment: ""),
            iconColor: DesignSystem.Colors.primaryBlue,
            action: {}
        )
        ImportActionTile(
            icon: "video.fill",
            title: NSLocalizedString("import.selectVideo", comment: ""),
            iconColor: DesignSystem.Colors.successGreen,
            style: .compact,
            action: {}
        )
    }
    .padding()
    .background(DesignSystem.Colors.backgroundPrimary)
}
