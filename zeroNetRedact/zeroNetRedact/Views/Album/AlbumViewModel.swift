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
    @Published var errorMessage: String?
    @Published var showError = false

    private let context = PersistenceController.shared.container.viewContext

    init() {
        loadGroups()
    }

    /// 加载所有分组
    func loadGroups() {
        allGroups = GroupManager.shared.getAllGroups()
        defaultGroup = GroupManager.shared.getDefaultGroup()
        customGroups = allGroups.filter { $0.sortOrder != 0 }

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

    // MARK: - 删除功能

    /// 删除单个脱敏文件
    func deleteFile(_ file: RedactedFile) {
        // 先取出属性值：对象删除并保存后属性会变成 nil，再访问非可选属性会崩溃
        let fileID = file.id
        let fileType = file.fileType

        // 1. 先删除 Core Data 记录并确认保存成功，避免"磁盘已删、记录还在"的孤立数据
        context.delete(file)
        do {
            try context.save()
        } catch {
            print("❌ 删除脱敏文件失败: \(error)")
            context.rollback()
            errorMessage = error.localizedDescription
            showError = true
            return
        }

        // 2. 记录已提交，再清理磁盘文件与缩略图缓存（失败仅记录日志）
        do {
            try StorageManager.shared.deleteRedacted(id: fileID, type: fileType)
        } catch {
            print("❌ 删除脱敏文件磁盘数据失败: \(fileID), \(error)")
        }
        let cacheKey = "redacted_thumbnail_\(fileID.uuidString)"
        ImageCache.shared.removeImage(forKey: cacheKey)

        // 3. 重新加载列表
        loadFiles()
        loadGroups()

        print("✅ 已删除脱敏文件: \(fileID)")
    }

    /// 批量删除脱敏文件：单次 Core Data save 代替逐个 save，避免 N 次全量刷新
    func deleteFiles(_ files: [RedactedFile]) {
        guard !files.isEmpty else { return }

        // 先快照属性：对象删除并保存后属性会变成 nil，再访问非可选属性会崩溃
        let snapshots = files.map { (id: $0.id, fileType: $0.fileType) }

        for file in files {
            context.delete(file)
        }

        do {
            try context.save()
        } catch {
            print("❌ 批量删除脱敏文件失败: \(error)")
            context.rollback()
            errorMessage = error.localizedDescription
            showError = true
            return
        }

        // Core Data 记录已提交，逐个清理磁盘文件与缩略图缓存（失败仅记录日志，不影响已提交的删除）
        for snapshot in snapshots {
            do {
                try StorageManager.shared.deleteRedacted(id: snapshot.id, type: snapshot.fileType)
            } catch {
                print("❌ 删除脱敏文件磁盘数据失败: \(snapshot.id), \(error)")
            }
            let cacheKey = "redacted_thumbnail_\(snapshot.id.uuidString)"
            ImageCache.shared.removeImage(forKey: cacheKey)
        }

        loadFiles()
        loadGroups()

        print("✅ 已批量删除 \(snapshots.count) 个脱敏文件")
    }
}
