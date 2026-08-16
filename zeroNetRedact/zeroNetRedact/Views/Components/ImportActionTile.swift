//
//  ImportActionTile.swift
//  ZeroNet Redact
//
//  首页导入操作卡片（空状态 2x2 导入引导）
//

import SwiftUI

/// 等尺寸导入操作卡片：左侧彩色图标 + 右侧标题（可选副标题）
struct ImportActionTile: View {
    private enum Metrics {
        static let iconSize: CGFloat = 44
        static let iconFontSize: CGFloat = 20
        static let iconCornerRadius: CGFloat = DesignSystem.CornerRadius.medium
        static let minHeight: CGFloat = 84
    }

    let icon: String
    let title: String
    var caption: String?
    let iconColor: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // 图标圆角底色
                Image(systemName: icon)
                    .font(.system(size: Metrics.iconFontSize, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.iconCornerRadius, style: .continuous)
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

                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Metrics.minHeight, alignment: .leading)
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

#Preview {
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
            action: {}
        )
    }
    .padding()
    .background(DesignSystem.Colors.backgroundPrimary)
}
