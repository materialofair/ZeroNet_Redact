//
//  ImportButtonBar.swift
//  ZeroNet Redact
//
//  底部导入按钮栏组件（有文件时显示）
//

import SwiftUI

struct ImportButtonBar: View {
    let onPhotosImport: () -> Void
    let onVideoImport: () -> Void
    let onDocumentImport: () -> Void
    let onStitch: () -> Void

    var body: some View {
        // 2x2 紧凑卡片网格，与空状态导入卡片保持同一套视觉语言
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible()),
            ],
            spacing: 10
        ) {
            ImportActionTile(
                icon: "photo.on.rectangle.angled",
                title: NSLocalizedString("import.selectPhotos", comment: ""),
                iconColor: DesignSystem.Colors.primaryBlue,
                style: .compact,
                action: onPhotosImport
            )

            ImportActionTile(
                icon: "video.fill",
                title: NSLocalizedString("import.selectVideo", comment: ""),
                iconColor: DesignSystem.Colors.successGreen,
                style: .compact,
                action: onVideoImport
            )

            ImportActionTile(
                icon: "doc.text.fill",
                title: NSLocalizedString("import.selectPDF", comment: ""),
                iconColor: DesignSystem.Colors.warningOrange,
                style: .compact,
                action: onDocumentImport
            )

            // 拼长图按钮(暂缓发布,由功能开关控制)
            if FeatureFlags.stitchEnabled {
                ImportActionTile(
                    icon: "rectangle.stack.badge.plus",
                    title: NSLocalizedString("stitch.button", comment: ""),
                    iconColor: DesignSystem.Colors.primaryPurple,
                    style: .compact,
                    action: onStitch
                )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, 10)
        .padding(.bottom, DesignSystem.Spacing.xl)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - 预览

#Preview {
    VStack {
        Spacer()
        ImportButtonBar(
            onPhotosImport: { print("Photos import") },
            onVideoImport: { print("Video import") },
            onDocumentImport: { print("Document import") },
            onStitch: { print("Stitch") }
        )
    }
}
