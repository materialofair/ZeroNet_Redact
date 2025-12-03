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
                Section(header: Text(NSLocalizedString("group.system", comment: ""))) {
                    if let defaultGroup = viewModel.defaultGroup {
                        GroupEditRow(
                            group: defaultGroup,
                            canDelete: false,
                            onUpdate: { viewModel.loadGroups() }
                        )
                    }
                }

                // 自定义分组
                Section(header: Text(NSLocalizedString("group.custom", comment: ""))) {
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
            .navigationTitle(NSLocalizedString("group.manage", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(
                NSLocalizedString("group.delete", comment: ""), isPresented: $showDeleteConfirmation
            ) {
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                    if let group = groupToDelete {
                        deleteGroup(group)
                    }
                }
            } message: {
                if let group = groupToDelete {
                    let groupName = group.name ?? NSLocalizedString("group.unnamed", comment: "")
                    let originalCount = GroupManager.shared.getFiles(in: group).count
                    let redactedCount = GroupManager.shared.getRedactedFiles(in: group).count

                    if originalCount == 0 && redactedCount == 0 {
                        Text(
                            String(
                                format: NSLocalizedString("group.deleteConfirm", comment: ""),
                                groupName))
                    } else if redactedCount == 0 {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "group.deleteOriginalMessage", comment: ""), groupName,
                                originalCount))
                    } else if originalCount == 0 {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "group.deleteRedactedMessage", comment: ""), groupName,
                                redactedCount))
                    } else {
                        Text(
                            String(
                                format: NSLocalizedString("group.deleteBothMessage", comment: ""),
                                groupName, originalCount, redactedCount))
                    }
                }
            }
            .alert(
                NSLocalizedString("group.deleteResult", comment: ""), isPresented: $showDeleteResult
            ) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
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
                        NSLocalizedString("group.name", comment: ""), text: $editedName,
                        onCommit: {
                            saveName()
                        }
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    Text(group.name ?? NSLocalizedString("group.unnamed", comment: ""))
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
                    Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
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
        case "folder.fill": return NSLocalizedString("icon.folder", comment: "")
        case "briefcase.fill": return NSLocalizedString("icon.briefcase", comment: "")
        case "house.fill": return NSLocalizedString("icon.house", comment: "")
        case "star.fill": return NSLocalizedString("icon.star", comment: "")
        case "heart.fill": return NSLocalizedString("icon.heart", comment: "")
        case "camera.fill": return NSLocalizedString("icon.camera", comment: "")
        case "doc.fill": return NSLocalizedString("icon.doc", comment: "")
        case "photo.fill": return NSLocalizedString("icon.photo", comment: "")
        case "film.fill": return NSLocalizedString("icon.film", comment: "")
        case "book.fill": return NSLocalizedString("icon.book", comment: "")
        default: return systemName
        }
    }
}

#Preview {
    GroupManagementSheet(viewModel: ImportViewModel())
}
