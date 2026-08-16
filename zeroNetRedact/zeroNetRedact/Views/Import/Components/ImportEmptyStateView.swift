//
//  ImportEmptyStateView.swift
//  ZeroNet Redact
//
//  导入页面空状态视图
//

import SwiftUI

struct ImportEmptyStateView: View {
    let onAction: (ImportAction) -> Void

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

    /// 导入按钮组视图 - 2x2 等尺寸网格（动作定义见 ImportAction）
    private var importButtonsView: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
                GridItem(.flexible()),
            ],
            spacing: DesignSystem.Spacing.md
        ) {
            ForEach(ImportAction.availableActions) { action in
                ImportActionTile(
                    icon: action.icon,
                    title: action.displayName,
                    caption: action.caption,
                    iconColor: action.iconColor,
                    action: { onAction(action) }
                )
            }
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, DesignSystem.Spacing.xxl)
    }
}
