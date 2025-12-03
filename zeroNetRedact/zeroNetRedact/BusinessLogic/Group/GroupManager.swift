//
//  GroupManager.swift
//  zeroNetRedact
//
//  Created by Claude on 2025-01-19.
//

import CoreData
import Foundation

/// 分组管理器 - 负责文件分组的CRUD操作
class GroupManager {
    static let shared = GroupManager()

    /// 默认分组的UUID（固定值，应用全局唯一）
    static let defaultGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private let context: NSManagedObjectContext

    private init() {
        self.context = PersistenceController.shared.container.viewContext
    }

    // MARK: - 默认分组管理

    /// 确保默认分组存在（应用启动时调用）
    func ensureDefaultGroup() {
        let fetchRequest: NSFetchRequest<FileGroup> = FileGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", Self.defaultGroupID as CVarArg)

        do {
            let results = try context.fetch(fetchRequest)
            if results.isEmpty {
                createDefaultGroup()
            }
        } catch {
            print("检查默认分组失败: \(error)")
            createDefaultGroup()
        }
    }

    /// 创建默认分组
    private func createDefaultGroup() {
        let defaultGroup = FileGroup(context: context)
        defaultGroup.id = Self.defaultGroupID
        defaultGroup.name = NSLocalizedString("group.default", comment: "")
        defaultGroup.createdAt = Date()
        defaultGroup.iconName = "folder.fill"
        defaultGroup.sortOrder = 0

        saveContext()
    }

    /// 获取默认分组
    func getDefaultGroup() -> FileGroup? {
        let fetchRequest: NSFetchRequest<FileGroup> = FileGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", Self.defaultGroupID as CVarArg)
        fetchRequest.fetchLimit = 1

        return try? context.fetch(fetchRequest).first
    }

    // MARK: - 分组CRUD操作

    /// 创建新分组
    @discardableResult
    func createGroup(name: String, iconName: String = "folder.fill") -> FileGroup? {
        let group = FileGroup(context: context)
        group.id = UUID()
        group.name = name
        group.createdAt = Date()
        group.iconName = iconName

        // 设置排序顺序为当前最大值+1
        let maxOrder =
            getAllGroups()
            .filter { $0.id != Self.defaultGroupID }  // 排除默认分组
            .map { $0.sortOrder }
            .max() ?? 0
        group.sortOrder = maxOrder + 1

        if saveContext() {
            return group
        }
        return nil
    }

    /// 获取所有分组（按sortOrder排序）
    func getAllGroups() -> [FileGroup] {
        let fetchRequest: NSFetchRequest<FileGroup> = FileGroup.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        return (try? context.fetch(fetchRequest)) ?? []
    }

    /// 获取自定义分组（排除默认分组）
    func getCustomGroups() -> [FileGroup] {
        return getAllGroups().filter { $0.id != Self.defaultGroupID }
    }

    /// 删除分组结果
    struct DeleteGroupResult {
        let success: Bool
        let message: String
        let originalFilesCount: Int
        let redactedFilesCount: Int
    }

    /// 删除分组（将分组内文件移至默认分组）
    func deleteGroup(_ group: FileGroup) -> DeleteGroupResult {
        // 不允许删除默认分组
        guard group.id != Self.defaultGroupID else {
            return DeleteGroupResult(
                success: false,
                message: NSLocalizedString("group.cannotDeleteDefault", comment: ""),
                originalFilesCount: 0,
                redactedFilesCount: 0
            )
        }

        // 将分组内的文件移至默认分组
        guard let defaultGroup = getDefaultGroup() else {
            return DeleteGroupResult(
                success: false,
                message: NSLocalizedString("group.cannotGetDefault", comment: ""),
                originalFilesCount: 0,
                redactedFilesCount: 0
            )
        }

        // 统计文件数量
        let originalFiles = Array((group.files as? Set<OriginalFile>) ?? [])
        let redactedFiles = Array((group.redactedFiles as? Set<RedactedFile>) ?? [])
        let originalCount = originalFiles.count
        let redactedCount = redactedFiles.count

        // 迁移原文件
        for file in originalFiles {
            file.group = defaultGroup
        }

        // 迁移脱敏文件
        for file in redactedFiles {
            file.group = defaultGroup
        }

        // 删除分组
        context.delete(group)

        // 保存并返回结果
        if saveContext() {
            let message: String
            if originalCount == 0 && redactedCount == 0 {
                message = NSLocalizedString("group.deletedEmpty", comment: "")
            } else if redactedCount == 0 {
                message = String(
                    format: NSLocalizedString("group.deletedWithOriginals", comment: ""),
                    originalCount)
            } else if originalCount == 0 {
                message = String(
                    format: NSLocalizedString("group.deletedWithRedacted", comment: ""),
                    redactedCount)
            } else {
                message = String(
                    format: NSLocalizedString("group.deletedWithBoth", comment: ""), originalCount,
                    redactedCount)
            }

            return DeleteGroupResult(
                success: true,
                message: message,
                originalFilesCount: originalCount,
                redactedFilesCount: redactedCount
            )
        } else {
            return DeleteGroupResult(
                success: false,
                message: NSLocalizedString("group.deleteFailed", comment: ""),
                originalFilesCount: 0,
                redactedFilesCount: 0
            )
        }
    }

    /// 重命名分组
    func renameGroup(_ group: FileGroup, newName: String) -> Bool {
        group.name = newName
        return saveContext()
    }

    /// 更新分组图标
    func updateGroupIcon(_ group: FileGroup, iconName: String) -> Bool {
        group.iconName = iconName
        return saveContext()
    }

    /// 更新分组排序
    func updateGroupsOrder(_ groups: [FileGroup]) -> Bool {
        for (index, group) in groups.enumerated() {
            group.sortOrder = Int16(index)
        }
        return saveContext()
    }

    // MARK: - 文件分组关联

    /// 移动文件到指定分组
    func moveFile(_ file: OriginalFile, to group: FileGroup) -> Bool {
        file.group = group
        return saveContext()
    }

    /// 批量移动文件到指定分组
    func moveFiles(_ files: [OriginalFile], to group: FileGroup) -> Bool {
        for file in files {
            file.group = group
        }
        return saveContext()
    }

    /// 获取分组内的文件
    func getFiles(in group: FileGroup) -> [OriginalFile] {
        guard let files = group.files as? Set<OriginalFile> else {
            return []
        }
        return Array(files).sorted { $0.createdAt > $1.createdAt }
    }

    /// 获取分组内的图片文件
    func getImages(in group: FileGroup) -> [OriginalImage] {
        return getFiles(in: group).compactMap { $0 as? OriginalImage }
    }

    /// 获取分组内的PDF文件
    func getPDFs(in group: FileGroup) -> [OriginalPDF] {
        return getFiles(in: group).compactMap { $0 as? OriginalPDF }
    }

    /// 获取分组统计信息
    func getGroupStatistics(_ group: FileGroup) -> (totalCount: Int, imageCount: Int, pdfCount: Int)
    {
        let files = getFiles(in: group)
        let imageCount = files.filter { $0 is OriginalImage }.count
        let pdfCount = files.filter { $0 is OriginalPDF }.count
        return (files.count, imageCount, pdfCount)
    }

    /// 获取分组内的脱敏文件
    func getRedactedFiles(in group: FileGroup) -> [RedactedFile] {
        guard let files = group.redactedFiles as? Set<RedactedFile> else {
            return []
        }
        return Array(files).sorted { $0.exportedAt > $1.exportedAt }
    }

    // MARK: - 数据迁移

    /// 迁移现有文件到默认分组（首次启动或更新后）
    func migrateExistingFiles() {
        // 确保默认分组存在
        ensureDefaultGroup()

        guard let defaultGroup = getDefaultGroup() else {
            print("无法获取默认分组，迁移失败")
            return
        }

        // 查找所有没有分组的文件
        let fetchRequest: NSFetchRequest<OriginalFile> = OriginalFile.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "group == nil")

        guard let orphanFiles = try? context.fetch(fetchRequest) else {
            print("查询孤立文件失败")
            return
        }

        if orphanFiles.isEmpty {
            print("没有需要迁移的文件")
            return
        }

        // 将所有文件归入默认分组
        for file in orphanFiles {
            file.group = defaultGroup
        }

        if saveContext() {
            print("成功迁移 \(orphanFiles.count) 个文件到默认分组")
        } else {
            print("迁移文件失败")
        }
    }

    // MARK: - 私有方法

    /// 保存上下文
    @discardableResult
    private func saveContext() -> Bool {
        if context.hasChanges {
            do {
                try context.save()
                return true
            } catch {
                print("保存Core Data失败: \(error)")
                context.rollback()
                return false
            }
        }
        return true
    }
}
