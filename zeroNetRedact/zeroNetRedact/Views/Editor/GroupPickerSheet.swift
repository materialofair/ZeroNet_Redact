import CoreData
import SwiftUI

struct GroupPickerSheet: View {
    @ObservedObject var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.allGroups, id: \.id) { group in
                    Button(action: {
                        viewModel.moveToGroup(group)
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            // 分组图标
                            Image(systemName: group.iconName ?? "folder.fill")
                                .font(.title3)
                                .foregroundColor(Color(hex: group.colorTag ?? "#8E8E93"))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(hex: group.colorTag ?? "#8E8E93").opacity(0.15))
                                )

                            // 分组信息
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name ?? NSLocalizedString("group.unnamed", comment: ""))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                let stats = GroupManager.shared.getGroupStatistics(group)
                                if stats.totalCount > 0 {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "group.fileCount", comment: ""), stats.totalCount)
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                } else {
                                    Text(NSLocalizedString("group.empty", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            // 当前分组标记
                            if group.id == viewModel.currentGroup?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(NSLocalizedString("group.moveTo", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Color.init(hex:) 已在 DesignSystem.swift 中定义

// Preview removed due to PersistenceController dependency
