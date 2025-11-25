//
//  CategoryBadge.swift
//  zeroNetRedact
//
//  Created by Claude on 2025-01-19.
//

import SwiftUI

/// 文件类型徽章 - 纯图标版本
struct CategoryBadge: View {
    let fileType: FileType

    var badgeConfig: (icon: String, color: Color) {
        switch fileType {
        case .image:
            return ("photo.fill", .blue)
        case .pdf:
            return ("doc.text.fill", .orange)
        }
    }

    var body: some View {
        Image(systemName: badgeConfig.icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(6)
            .background(
                badgeConfig.color
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            )
            .clipShape(Circle())
    }
}

#Preview {
    VStack(spacing: 12) {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)

            CategoryBadge(fileType: .image)
                .padding(8)
        }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)

            CategoryBadge(fileType: .pdf)
                .padding(8)
        }
    }
    .padding()
}
