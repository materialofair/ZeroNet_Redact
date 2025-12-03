//
//  GroupInfoBar.swift
//  zeroNetRedact
//
//  Created by Claude on 2025-01-19.
//

import CoreData
import SwiftUI

/// 当前分组信息栏
struct GroupInfoBar: View {
    let group: FileGroup
    let onEdit: () -> Void

    var statistics: (totalCount: Int, imageCount: Int, pdfCount: Int) {
        GroupManager.shared.getGroupStatistics(group)
    }

    var body: some View {
        HStack {
            // 分组图标和名称
            HStack(spacing: 8) {
                Image(systemName: group.iconName ?? "folder.fill")
                    .foregroundColor(colorFromHex(group.colorTag ?? "#8E8E93"))

                Text(group.name ?? NSLocalizedString("group.unnamed", comment: ""))
                    .font(.headline)
            }

            Spacer()

            // 文件统计
            HStack(spacing: 4) {
                if statistics.imageCount > 0 {
                    Label("\(statistics.imageCount)", systemImage: "photo")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                if statistics.imageCount > 0 && statistics.pdfCount > 0 {
                    Text("·")
                        .foregroundColor(.secondary)
                }

                if statistics.pdfCount > 0 {
                    Label("\(statistics.pdfCount)", systemImage: "doc")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if statistics.totalCount == 0 {
                    Text(NSLocalizedString("group.empty", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 编辑按钮
            Button(action: onEdit) {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
    }

    /// 从十六进制字符串转换为Color
    private func colorFromHex(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }
}

#Preview {
    VStack(spacing: 0) {
        GroupInfoBar(
            group: {
                let group = FileGroup()
                group.name = "默认分组"
                group.iconName = "folder.fill"
                group.colorTag = "#8E8E93"
                return group
            }(),
            onEdit: {
                print("编辑分组")
            }
        )

        GroupInfoBar(
            group: {
                let group = FileGroup()
                group.name = "工作文件"
                group.iconName = "briefcase.fill"
                group.colorTag = "#007AFF"
                return group
            }(),
            onEdit: {
                print("编辑分组")
            }
        )
    }
}
