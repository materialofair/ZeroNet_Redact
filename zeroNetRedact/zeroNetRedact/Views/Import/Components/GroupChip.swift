//
//  GroupChip.swift
//  zeroNetRedact
//
//  Created by Claude on 2025-01-19.
//

import CoreData
import SwiftUI

/// 分组标签组件 - iOS Tab样式
struct GroupChip: View {
    let group: FileGroup
    let isSelected: Bool
    let fileCount: Int

    var body: some View {
        VStack(spacing: 6) {
            // 纯文本显示
            Text(group.name ?? "未命名")
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                .lineLimit(1)

            // 选中状态的高亮线条
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(height: 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 0) {
            GroupChip(
                group: {
                    let group = FileGroup()
                    group.name = "默认分组"
                    group.iconName = "folder.fill"
                    return group
                }(),
                isSelected: true,
                fileCount: 5
            )

            GroupChip(
                group: {
                    let group = FileGroup()
                    group.name = "工作文件"
                    group.iconName = "briefcase.fill"
                    return group
                }(),
                isSelected: false,
                fileCount: 12
            )

            GroupChip(
                group: {
                    let group = FileGroup()
                    group.name = "生活"
                    group.iconName = "house.fill"
                    return group
                }(),
                isSelected: false,
                fileCount: 3
            )
        }

        Divider()

        Text("iOS Tab 样式预览")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
}
