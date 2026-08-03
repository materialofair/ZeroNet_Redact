//
//  ImportEmptyStateView.swift
//  ZeroNet Redact
//
//  导入页面空状态视图
//

import SwiftUI

struct ImportEmptyStateView: View {
    let onPhotosImport: () -> Void
    let onVideoImport: () -> Void
    let onDocumentImport: () -> Void
    let onStitch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // 图标组合 - 盾牌 + 光晕
                headerIconView

                // 标题和描述
                titleView

                // 导入按钮组 - 横向排列
                importButtonsView
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - 子视图

    /// 头部图标视图
    private var headerIconView: some View {
        ZStack {
            // 外层光晕
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            DesignSystem.Colors.primaryBlue.opacity(0.12),
                            DesignSystem.Colors.primaryPurple.opacity(0.04),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 25,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)

            // 内层圆形背景
            Circle()
                .fill(DesignSystem.Gradients.lightBackground)
                .frame(width: 80, height: 80)

            // 盾牌图标
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(DesignSystem.Gradients.primary)
        }
    }

    /// 标题和描述视图
    private var titleView: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("import.empty.title", comment: ""))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text(NSLocalizedString("import.empty.description", comment: ""))
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    /// 导入按钮组视图 - 2x2 等尺寸网格
    private var importButtonsView: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
                GridItem(.flexible()),
            ],
            spacing: DesignSystem.Spacing.md
        ) {
            // 从相册导入图片 —— 单次选择上限提示只跟图片按钮关联（该上限不适用于 PDF）
            ImportActionTile(
                icon: "photo.on.rectangle.angled",
                title: NSLocalizedString("import.selectPhotos", comment: ""),
                caption: NSLocalizedString("import.maxSelection", comment: ""),
                iconColor: DesignSystem.Colors.primaryBlue,
                action: onPhotosImport
            )

            // 导入视频
            ImportActionTile(
                icon: "video.fill",
                title: NSLocalizedString("import.selectVideo", comment: ""),
                iconColor: DesignSystem.Colors.successGreen,
                action: onVideoImport
            )

            // 导入PDF文件
            ImportActionTile(
                icon: "doc.text.fill",
                title: NSLocalizedString("import.selectPDF", comment: ""),
                iconColor: DesignSystem.Colors.warningOrange,
                action: onDocumentImport
            )

            // 拼接长图(暂缓发布,由功能开关控制)
            if FeatureFlags.stitchEnabled {
                ImportActionTile(
                    icon: "rectangle.stack.badge.plus",
                    title: NSLocalizedString("stitch.button", comment: ""),
                    iconColor: DesignSystem.Colors.primaryPurple,
                    action: onStitch
                )
            }
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, DesignSystem.Spacing.xxl)
    }
}

// MARK: - 导入操作卡片组件

/// 等尺寸导入操作卡片：左侧彩色图标 + 右侧标题（可选副标题）
private struct ImportActionTile: View {
    let icon: String
    let title: String
    var caption: String?
    let iconColor: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // 图标圆角底色
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                            .fill(iconColor.opacity(colorScheme == .dark ? 0.24 : 0.12))
                    )

                // 标题 + 可选副标题
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
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
        .buttonStyle(ActionTileButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(caption ?? "")
    }
}

/// 导入卡片按压反馈
private struct ActionTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 预览

#Preview {
    ImportEmptyStateView(
        onPhotosImport: { print("Photos import") },
        onVideoImport: { print("Video import") },
        onDocumentImport: { print("Document import") },
        onStitch: {}
    )
}
