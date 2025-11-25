//
//  GroupManagementSheet.swift
//  zeroNetRedact
//
//  Created by Claude on 2025-01-19.
//

import SwiftUI

/// 管理分组界面
struct GroupManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ImportViewModel

    @State private var showDeleteConfirmation: Bool = false
    @State private var groupToDelete: FileGroup?
    @State private var deleteResultMessage: String = ""
    @State private var showDeleteResult: Bool = false

    var body: some View {
        NavigationView {
            List {
                // 默认分组（不可删除，仅可重命名）
                Section(header: Text("系统分组")) {
                    if let defaultGroup = viewModel.defaultGroup {
                        GroupEditRow(
                            group: defaultGroup,
                            canDelete: false,
                            onUpdate: { viewModel.loadGroups() }
                        )
                    }
                }

                // 自定义分组
                Section(header: Text("自定义分组")) {
                    ForEach(viewModel.customGroups, id: \.id) { group in
                        GroupEditRow(
                            group: group,
                            canDelete: true,
                            onUpdate: { viewModel.loadGroups() },
                            onDelete: {
                                groupToDelete = group
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
            }
            .navigationTitle("管理分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("删除分组", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let group = groupToDelete {
                        deleteGroup(group)
                    }
                }
            } message: {
                if let group = groupToDelete {
                    let groupName = group.name ?? "未命名"
                    let originalCount = GroupManager.shared.getFiles(in: group).count
                    let redactedCount = GroupManager.shared.getRedactedFiles(in: group).count

                    if originalCount == 0 && redactedCount == 0 {
                        Text("确定删除「\(groupName)」吗？")
                    } else if redactedCount == 0 {
                        Text("删除「\(groupName)」后，\(originalCount)个原文件将移至默认分组")
                    } else if originalCount == 0 {
                        Text("删除「\(groupName)」后，\(redactedCount)个脱敏文件将移至默认分组")
                    } else {
                        Text(
                            "删除「\(groupName)」后：\n• \(originalCount)个原文件\n• \(redactedCount)个脱敏文件\n将全部移至默认分组"
                        )
                    }
                }
            }
            .alert("删除结果", isPresented: $showDeleteResult) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(deleteResultMessage)
            }
        }
    }

    private func deleteGroup(_ group: FileGroup) {
        let result = GroupManager.shared.deleteGroup(group)

        if result.success {
            viewModel.loadGroups()

            // 如果删除的是当前选中的分组，切换到默认分组
            if viewModel.selectedGroup?.id == group.id {
                viewModel.selectGroup(viewModel.defaultGroup)
            }

            // 显示成功提示
            deleteResultMessage = result.message
            showDeleteResult = true
        } else {
            // 显示失败提示
            deleteResultMessage = result.message
            showDeleteResult = true
        }

        groupToDelete = nil
    }
}

/// 分组编辑行
struct GroupEditRow: View {
    @ObservedObject var group: FileGroup
    let canDelete: Bool
    let onUpdate: () -> Void
    var onDelete: (() -> Void)?

    @State private var isEditing: Bool = false
    @State private var editedName: String = ""

    // 可选图标
    private let availableIcons = [
        "folder.fill", "briefcase.fill", "house.fill",
        "star.fill", "heart.fill", "camera.fill",
        "doc.fill", "photo.fill", "film.fill", "book.fill",
    ]

    var fileCount: Int {
        GroupManager.shared.getFiles(in: group).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // 图标选择
                Menu {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button(action: {
                            if GroupManager.shared.updateGroupIcon(group, iconName: icon) {
                                onUpdate()
                            }
                        }) {
                            Label(iconName(icon), systemImage: icon)
                        }
                    }
                } label: {
                    Image(systemName: group.iconName ?? "folder.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                }

                // 名称编辑
                if isEditing {
                    TextField(
                        "分组名称", text: $editedName,
                        onCommit: {
                            saveName()
                        }
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    Text(group.name ?? "未命名")
                        .font(.headline)
                }

                Spacer()

                // 文件数量
                Text("(\(fileCount))")
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                // 编辑按钮
                Button(action: {
                    if isEditing {
                        saveName()
                    } else {
                        editedName = group.name ?? ""
                        isEditing = true
                    }
                }) {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                        .foregroundColor(isEditing ? .green : .blue)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete {
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func saveName() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && GroupManager.shared.renameGroup(group, newName: trimmedName) {
            onUpdate()
        }
        isEditing = false
    }

    private func iconName(_ systemName: String) -> String {
        switch systemName {
        case "folder.fill": return "文件夹"
        case "briefcase.fill": return "公文包"
        case "house.fill": return "房子"
        case "star.fill": return "星星"
        case "heart.fill": return "心形"
        case "camera.fill": return "相机"
        case "doc.fill": return "文档"
        case "photo.fill": return "照片"
        case "film.fill": return "影片"
        case "book.fill": return "书籍"
        default: return systemName
        }
    }
}

#Preview {
    GroupManagementSheet(viewModel: ImportViewModel())
}
