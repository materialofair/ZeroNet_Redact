//
//  RedactedGroupSelectorBar.swift
//  zeroNetRedact
//
//  分组选择器 - 用于脱敏文件（iOS Tab样式）
//

import SwiftUI

/// 脱敏文件分组选择器（横向滚动）- iOS Tab样式
struct RedactedGroupSelectorBar: View {
    @ObservedObject var viewModel: AlbumViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // 默认分组（始终第一位）
                if let defaultGroup = viewModel.defaultGroup {
                    GroupChip(
                        group: defaultGroup,
                        isSelected: viewModel.selectedGroup?.id == defaultGroup.id,
                        fileCount: GroupManager.shared.getRedactedFiles(in: defaultGroup).count
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectGroup(defaultGroup)
                        }
                    }
                }

                // 自定义分组
                ForEach(viewModel.customGroups, id: \.id) { group in
                    GroupChip(
                        group: group,
                        isSelected: viewModel.selectedGroup?.id == group.id,
                        fileCount: GroupManager.shared.getRedactedFiles(in: group).count
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectGroup(group)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
