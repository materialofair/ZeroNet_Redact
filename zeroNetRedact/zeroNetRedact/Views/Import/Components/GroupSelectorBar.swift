//
//  GroupSelectorBar.swift
//  zeroNetRedact
//
//  Created by Claude on 2025-01-19.
//

import SwiftUI

/// 分组选择器（横向滚动）- iOS Tab样式
struct GroupSelectorBar: View {
    @ObservedObject var viewModel: ImportViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // 默认分组（始终第一位）
                if let defaultGroup = viewModel.defaultGroup {
                    GroupChip(
                        group: defaultGroup,
                        isSelected: viewModel.selectedGroup?.id == defaultGroup.id,
                        fileCount: GroupManager.shared.getFiles(in: defaultGroup).count
                    )
                    .onTapGesture {
                        viewModel.selectGroup(defaultGroup)
                    }
                }

                // 自定义分组
                ForEach(viewModel.customGroups, id: \.id) { group in
                    GroupChip(
                        group: group,
                        isSelected: viewModel.selectedGroup?.id == group.id,
                        fileCount: GroupManager.shared.getFiles(in: group).count
                    )
                    .onTapGesture {
                        viewModel.selectGroup(group)
                    }
                }

                // 新建分组按钮 - 纯"+"图标
                Button(action: { viewModel.showCreateGroup = true }) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, 4)
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        GroupSelectorBar(viewModel: ImportViewModel())

        Divider()

        Text("iOS Tab 样式分组选择器")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
    }
}
