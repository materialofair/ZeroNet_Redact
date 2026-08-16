//
//  FileTypeFilterBar.swift
//  ZeroNet Redact
//
//  列表工具条：文件类型筛选（全部/图片/PDF/视频）+ 排序菜单
//  导入页与相册页共用（filterType 此前是死代码，无任何 UI 绑定）
//

import SwiftUI

/// 列表排序选项（导入页按创建时间/大小，相册页按导出时间/大小）
enum FileSortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case largest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest: return NSLocalizedString("list.sort.newest", comment: "")
        case .oldest: return NSLocalizedString("list.sort.oldest", comment: "")
        case .largest: return NSLocalizedString("list.sort.largest", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .largest: return "arrow.down.to.line"
        }
    }
}

/// 文件类型筛选条 + 排序菜单
struct FileTypeFilterBar: View {
    @Binding var filterType: FileType?
    @Binding var sortOption: FileSortOption

    var body: some View {
        HStack(spacing: 6) {
            ForEach([nil, FileType.image, .pdf, .video], id: \.self) { type in
                Button {
                    filterType = type
                } label: {
                    Text(
                        type?.displayName
                            ?? NSLocalizedString("list.filter.all", comment: "")
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        filterType == type
                            ? DesignSystem.Colors.primaryBlue
                            : DesignSystem.Colors.backgroundSecondary,
                        in: Capsule()
                    )
                    .foregroundColor(
                        filterType == type ? .white : DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filterType == type ? .isSelected : [])
            }

            Spacer()

            Menu {
                ForEach(FileSortOption.allCases) { option in
                    Button {
                        sortOption = option
                    } label: {
                        if sortOption == option {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Label(option.displayName, systemImage: option.icon)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(NSLocalizedString("list.sort.label", comment: ""))
            .accessibilityValue(sortOption.displayName)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var filter: FileType? = nil
        @State private var sort: FileSortOption = .newest

        var body: some View {
            FileTypeFilterBar(filterType: $filter, sortOption: $sort)
                .padding(.vertical, 12)
        }
    }
    return PreviewHost()
}
