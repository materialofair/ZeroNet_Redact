//
//  CreateGroupSheet.swift
//  zeroNetRedact
//
//  Created by Claude on 2025-01-19.
//

import SwiftUI

/// 新建分组弹窗
struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ImportViewModel

    @State private var groupName: String = ""
    @State private var selectedIcon: String = "folder.fill"
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // 可选图标
    private let availableIcons = [
        "folder.fill", "briefcase.fill", "house.fill",
        "star.fill", "heart.fill", "camera.fill",
        "doc.fill", "photo.fill", "film.fill", "book.fill",
    ]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("分组信息")) {
                    // 名称输入
                    TextField("分组名称", text: $groupName)
                        .autocapitalization(.none)
                }

                Section(header: Text("图标")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 12) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Button(action: {
                                selectedIcon = icon
                            }) {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        selectedIcon == icon
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.gray.opacity(0.1)
                                    )
                                    .cornerRadius(8)
                                    .foregroundColor(selectedIcon == icon ? .accentColor : .primary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // 预览
                Section(header: Text("预览")) {
                    HStack {
                        Image(systemName: selectedIcon)
                            .foregroundColor(.accentColor)
                        Text(groupName.isEmpty ? "新分组" : groupName)
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("新建分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        createGroup()
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func createGroup() {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "分组名称不能为空"
            showError = true
            return
        }

        if GroupManager.shared.createGroup(
            name: trimmedName,
            iconName: selectedIcon
        ) != nil {
            viewModel.loadGroups()
            dismiss()
        } else {
            errorMessage = "创建分组失败，请重试"
            showError = true
        }
    }
}

#Preview {
    CreateGroupSheet(viewModel: ImportViewModel())
}
