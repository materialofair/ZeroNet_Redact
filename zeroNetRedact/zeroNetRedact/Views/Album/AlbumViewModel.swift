import Combine
import CoreData
import SwiftUI

@MainActor
class AlbumViewModel: ObservableObject {
    @Published var redactedFiles: [RedactedFile] = []
    @Published var filterType: FileType?

    // 分组相关
    @Published var allGroups: [FileGroup] = []
    @Published var defaultGroup: FileGroup?
    @Published var customGroups: [FileGroup] = []
    @Published var selectedGroup: FileGroup?
    @Published var showCreateGroup = false
    @Published var showManageGroups = false

    private let context = PersistenceController.shared.container.viewContext

    init() {
        loadGroups()
    }

    /// 加载所有分组
    func loadGroups() {
        allGroups = GroupManager.shared.getAllGroups()
        defaultGroup = GroupManager.shared.getDefaultGroup()
        customGroups = allGroups.filter { !($0.name == "默认分组" && $0.sortOrder == 0) }

        // 如果没有选中分组，默认选中默认分组
        if selectedGroup == nil {
            selectedGroup = defaultGroup
        }
    }

    /// 选择分组
    func selectGroup(_ group: FileGroup) {
        selectedGroup = group
        loadFiles()
    }

    /// 加载脱敏文件列表
    func loadFiles() {
        let request: NSFetchRequest<RedactedFile> = RedactedFile.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "exportedAt", ascending: false)]

        // 构建谓词
        var predicates: [NSPredicate] = []

        // 根据选中的分组过滤
        if let group = selectedGroup {
            predicates.append(NSPredicate(format: "group == %@", group))
        }

        // 根据文件类型过滤
        if let type = filterType {
            predicates.append(NSPredicate(format: "fileTypeRaw == %@", type.rawValue))
        }

        // 组合谓词
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        do {
            redactedFiles = try context.fetch(request)
            print("📸 AlbumViewModel: 加载了 \(redactedFiles.count) 个脱敏文件")

            // 调试信息
            for (index, file) in redactedFiles.enumerated() {
                print(
                    "  脱敏文件\(index + 1): ID=\(file.id), 类型=\(file.fileType), 导出时间=\(file.exportedAt), 分组=\(file.group?.name ?? "无")"
                )
            }
        } catch {
            print("❌ 加载脱敏文件失败: \(error)")
            redactedFiles = []
        }
    }

    /// 移动文件到分组
    func moveFileToGroup(_ file: RedactedFile, group: FileGroup) {
        file.group = group
        do {
            try context.save()
            print("✅ 脱敏文件已移动到分组: \(group.name ?? "未命名")")
            loadFiles()
        } catch {
            print("❌ 移动脱敏文件到分组失败: \(error)")
        }
    }
}
