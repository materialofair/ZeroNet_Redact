//
//  ImportEmptyStateView.swift
//  ZeroNet Redact
//
//  导入页面空状态视图
//

import SwiftUI

struct ImportEmptyStateView: View {
    let onPhotosImport: () -> Void
    let onDocumentImport: () -> Void

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
            Text("零网隐私保护")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("文件加密存储,只有你能访问")
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    /// 导入按钮组视图
    private var importButtonsView: some View {
        HStack(spacing: 12) {
            // 从相册导入图片
            ImportButton(
                icon: "photo.on.rectangle.angled",
                title: "选择图片",
                iconColor: DesignSystem.Colors.primaryBlue,
                action: onPhotosImport
            )

            // 导入PDF文件
            ImportButton(
                icon: "doc.text.fill",
                title: "选择 PDF",
                iconColor: DesignSystem.Colors.warningOrange,
                action: onDocumentImport
            )
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - 导入按钮组件

private struct ImportButton: View {
    let icon: String
    let title: String
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // 图标圆形背景
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(iconColor)
                }

                // 标题
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(DesignSystem.Colors.backgroundCard)
            .cornerRadius(DesignSystem.CornerRadius.large)
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 预览

#Preview {
    ImportEmptyStateView(
        onPhotosImport: { print("Photos import") },
        onDocumentImport: { print("Document import") }
    )
}
