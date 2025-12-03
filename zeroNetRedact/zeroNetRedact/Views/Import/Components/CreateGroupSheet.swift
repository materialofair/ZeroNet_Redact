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
                Section(header: Text(NSLocalizedString("group.info", comment: ""))) {
                    // 名称输入
                    TextField(NSLocalizedString("group.name", comment: ""), text: $groupName)
                        .autocapitalization(.none)
                }

                Section(header: Text(NSLocalizedString("group.icon", comment: ""))) {
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
                Section(header: Text(NSLocalizedString("group.preview", comment: ""))) {
                    HStack {
                        Image(systemName: selectedIcon)
                            .foregroundColor(.accentColor)
                        Text(
                            groupName.isEmpty
                                ? NSLocalizedString("group.new", comment: "") : groupName
                        )
                        .font(.headline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(NSLocalizedString("group.create", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.create", comment: "")) {
                        createGroup()
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(NSLocalizedString("common.error", comment: ""), isPresented: $showError) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func createGroup() {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = NSLocalizedString("group.nameEmpty", comment: "")
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
            errorMessage = NSLocalizedString("group.createFailed", comment: "")
            showError = true
        }
    }
}

#Preview {
    CreateGroupSheet(viewModel: ImportViewModel())
}
