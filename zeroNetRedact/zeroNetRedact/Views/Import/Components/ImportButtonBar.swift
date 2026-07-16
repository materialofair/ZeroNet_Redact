//
//  ImportButtonBar.swift
//  ZeroNet Redact
//
//  底部导入按钮栏组件
//

import SwiftUI

struct ImportButtonBar: View {
    let onPhotosImport: () -> Void
    let onDocumentImport: () -> Void
    let onStitch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 导入图片按钮
            ActionButton(
                icon: "photo.on.rectangle.angled",
                title: NSLocalizedString("import.selectPhotos", comment: ""),
                gradient: DesignSystem.Gradients.primary,
                action: onPhotosImport
            )

            // 导入PDF按钮
            ActionButton(
                icon: "doc.text.fill",
                title: NSLocalizedString("import.selectPDF", comment: ""),
                gradient: DesignSystem.Gradients.pdfType,
                action: onDocumentImport
            )

            // 拼长图按钮(暂缓发布,由功能开关控制)
            if FeatureFlags.stitchEnabled {
                ActionButton(
                    icon: "rectangle.stack.badge.plus",
                    title: NSLocalizedString("stitch.button", comment: ""),
                    gradient: DesignSystem.Gradients.primary,
                    action: onStitch
                )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - 操作按钮组件

private struct ActionButton: View {
    let icon: String
    let title: String
    let gradient: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(gradient)
            .foregroundColor(.white)
            .cornerRadius(DesignSystem.CornerRadius.medium)
        }
    }
}

// MARK: - 预览

#Preview {
    VStack {
        Spacer()
        ImportButtonBar(
            onPhotosImport: { print("Photos import") },
            onDocumentImport: { print("Document import") },
            onStitch: { print("Stitch") }
        )
    }
}
