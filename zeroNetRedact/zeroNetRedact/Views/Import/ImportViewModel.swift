import Combine
import CoreData
import PhotosUI
import SwiftUI

@MainActor
class ImportViewModel: ObservableObject {
    @Published var showPhotosPicker = false
    @Published var showDocumentPicker = false

    // 导入进度
    @Published var isImporting = false
    @Published var importCompletedCount = 0
    @Published var importTotalCount = 0

    // 错误提示（仅用于真正的导入失败）
    @Published var showError = false
    @Published var errorMessage: String?

    // 导入结果提示（成功+跳过重复，非错误场景）
    @Published var showImportResultAlert = false
    @Published var importResultMessage = ""
    @Published var pendingDuplicateSources: [ImportSource] = []

    // 成功 Toast（无重复、无失败时的轻量反馈）
    @Published var showSuccessToast = false
    @Published var successToastMessage = ""

    // 原始文件列表
    @Published var originalFiles: [OriginalFile] = []
    @Published var filterType: FileType? = nil

    // 分组管理
    @Published var allGroups: [FileGroup] = []
    @Published var customGroups: [FileGroup] = []
    @Published var defaultGroup: FileGroup?
    @Published var selectedGroup: FileGroup?
    @Published var showCreateGroup = false
    @Published var showManageGroups = false

    // 多选删除
    @Published var isSelectionMode = false
    @Published var selectedFileIDs: Set<UUID> = []
    @Published var showBatchDeleteConfirm = false

    private var importCancelled = false
    private var successToastTask: Task<Void, Never>?
    private let importManager = ImportManager.shared
    private let groupManager = GroupManager.shared
    private let context = PersistenceController.shared.container.viewContext

    init() {
        loadGroups()
        loadOriginalFiles()
    }

    // MARK: - 分组管理

    func loadGroups() {
        allGroups = groupManager.getAllGroups()
        customGroups = groupManager.getCustomGroups()
        defaultGroup = groupManager.getDefaultGroup()

        // 如果没有选中分组，默认选中默认分组
        if selectedGroup == nil {
            selectedGroup = defaultGroup
        }

        print("📁 ImportViewModel: 加载了 \(allGroups.count) 个分组")
    }

    func selectGroup(_ group: FileGroup?) {
        selectedGroup = group
        // 切分组后旧分组的多选状态不再有意义，避免"删除(N)"悬空
        selectedFileIDs.removeAll()
        isSelectionMode = false
        loadOriginalFiles()
    }

    // MARK: - 加载原始文件列表

    func loadOriginalFiles() {
        let request: NSFetchRequest<OriginalFile> = OriginalFile.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        // 构建谓词
        var predicates: [NSPredicate] = []

        // 根据选中的分组筛选
        if let selectedGroup = selectedGroup {
            predicates.append(NSPredicate(format: "group == %@", selectedGroup))
        }

        // 根据过滤类型添加谓词
        if let filterType = filterType {
            predicates.append(NSPredicate(format: "fileTypeRaw == %@", filterType.rawValue))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        do {
            originalFiles = try context.fetch(request)
            print("📂 ImportViewModel: 加载了 \(originalFiles.count) 个原始文件")
        } catch {
            print("❌ 加载原始文件失败: \(error)")
            originalFiles = []
        }
    }

    // MARK: - 导入功能

    func importPhotos(_ items: [PhotosPickerItem]) async {
        var sources: [ImportSource] = []
        var loadFailedCount = 0
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                sources.append(.imageData(data))
            } else {
                loadFailedCount += 1
            }
        }
        await performBatchImport(sources, loadFailedCount: loadFailedCount)
    }

    func importDocuments(_ urls: [URL]) async {
        let sources = urls.map { ImportSource.fileURL($0) }
        await performBatchImport(sources)
    }

    /// 取消正在进行的批量导入：已完成的文件保留，剩余文件停止处理
    func cancelImport() {
        importCancelled = true
    }

    /// 用户在结果提示中选择"仍然导入"被跳过的重复文件
    func forceImportPendingDuplicates() async {
        let sources = pendingDuplicateSources
        pendingDuplicateSources = []
        guard !sources.isEmpty else { return }

        isImporting = true
        importCancelled = false
        importCompletedCount = 0
        importTotalCount = sources.count
        defer {
            isImporting = false
            importCompletedCount = 0
            importTotalCount = 0
        }

        var successCount = 0

        for (index, source) in sources.enumerated() {
            if importCancelled { break }

            do {
                let file = try await importManager.importFile(from: source)
                attachToSelectedGroup(file)
                successCount += 1
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }

            importCompletedCount = index + 1
        }

        loadOriginalFiles()

        if successCount > 0 {
            presentSuccessToast(
                String(format: NSLocalizedString("import.success.toast", comment: ""), successCount))
        }
    }

    /// 用户在结果提示中选择保留跳过状态（放弃导入重复文件）
    func dismissPendingDuplicates() {
        pendingDuplicateSources = []
    }

    private func attachToSelectedGroup(_ file: RedactableFile) {
        let targetGroup = selectedGroup ?? defaultGroup
        if let group = targetGroup, let originalFile = file as? OriginalFile {
            _ = groupManager.moveFile(originalFile, to: group)
        }
    }

    /// 显示成功 Toast，2 秒后自动消失。连续触发时取消旧的自动消失任务，避免旧任务把新 Toast 误关。
    private func presentSuccessToast(_ message: String) {
        successToastTask?.cancel()
        successToastMessage = message
        showSuccessToast = true
        successToastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.showSuccessToast = false
        }
    }

    /// 将 `.fileURL` 来源当场读入内存转成 `.pdfData`，避免 sheet dismiss 后安全作用域 URL 失效；
    /// 其余来源（已是内存数据）原样返回。读取失败返回 nil。
    private func snapshotFileURLSource(_ source: ImportSource) async -> ImportSource? {
        guard case .fileURL(let url) = source else { return source }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return .pdfData(data)
    }

    /// 串行批量导入：逐项做重复检测，同时上报进度、支持取消。
    /// 未改用 ImportManager.batchImport 的并发实现——重复检测依赖对 Core Data 的顺序查询，
    /// 并发处理会导致同一批次内互相重复的文件都被判定为"非重复"，破坏一致性，因此保留串行。
    /// - Parameter loadFailedCount: 调用方在生成 sources 前已经发生的读取失败数（例如照片 loadTransferable 失败）
    private func performBatchImport(_ sources: [ImportSource], loadFailedCount: Int = 0) async {
        guard !sources.isEmpty else {
            if loadFailedCount > 0 {
                importResultMessage = String(
                    format: NSLocalizedString("import.photo.loadFailedCount", comment: ""),
                    loadFailedCount)
                showImportResultAlert = true
            }
            return
        }

        isImporting = true
        importCancelled = false
        importCompletedCount = 0
        importTotalCount = sources.count
        defer {
            isImporting = false
            importCompletedCount = 0
            importTotalCount = 0
        }

        var successCount = 0
        var duplicates: [ImportSource] = []
        var cancelledCount = 0
        var totalLoadFailedCount = loadFailedCount

        for (index, source) in sources.enumerated() {
            if importCancelled {
                cancelledCount = sources.count - index
                break
            }

            do {
                let result = try await importManager.importFileWithDuplicateCheck(from: source)
                switch result {
                case .success(let file):
                    attachToSelectedGroup(file)
                    successCount += 1

                case .duplicate:
                    // fileURL 来源当场转成内存数据，避免用户稍后点"仍然导入"时安全作用域已失效
                    if let resolved = await snapshotFileURLSource(source) {
                        duplicates.append(resolved)
                    } else {
                        totalLoadFailedCount += 1
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }

            importCompletedCount = index + 1
        }

        loadOriginalFiles()
        presentBatchResult(
            successCount: successCount, duplicateSources: duplicates, cancelledCount: cancelledCount,
            loadFailedCount: totalLoadFailedCount)

        print("✅ 批量导入完成：成功 \(successCount)，重复 \(duplicates.count)，取消 \(cancelledCount)")
    }

    private func presentBatchResult(
        successCount: Int, duplicateSources: [ImportSource], cancelledCount: Int,
        loadFailedCount: Int = 0
    ) {
        if !duplicateSources.isEmpty {
            pendingDuplicateSources = duplicateSources
            var message = String(
                format: NSLocalizedString("import.duplicate.batch_result", comment: ""),
                successCount, duplicateSources.count)
            if cancelledCount > 0 {
                message +=
                    "\n"
                    + String(
                        format: NSLocalizedString("import.cancelled.remaining", comment: ""),
                        cancelledCount)
            }
            if loadFailedCount > 0 {
                message +=
                    "\n"
                    + String(
                        format: NSLocalizedString("import.photo.loadFailedCount", comment: ""),
                        loadFailedCount)
            }
            importResultMessage = message
            showImportResultAlert = true
        } else if cancelledCount > 0 {
            var message = String(
                format: NSLocalizedString("import.cancelled.result", comment: ""), successCount,
                cancelledCount)
            if loadFailedCount > 0 {
                message +=
                    "\n"
                    + String(
                        format: NSLocalizedString("import.photo.loadFailedCount", comment: ""),
                        loadFailedCount)
            }
            importResultMessage = message
            showImportResultAlert = true
        } else if loadFailedCount > 0 {
            var message = String(
                format: NSLocalizedString("import.success.toast", comment: ""), successCount)
            message +=
                "\n"
                + String(
                    format: NSLocalizedString("import.photo.loadFailedCount", comment: ""),
                    loadFailedCount)
            importResultMessage = message
            showImportResultAlert = true
        } else if successCount > 0 {
            presentSuccessToast(
                String(format: NSLocalizedString("import.success.toast", comment: ""), successCount))
        }
    }

    // MARK: - 文件移动

    func moveFile(_ file: OriginalFile, to group: FileGroup) {
        if groupManager.moveFile(file, to: group) {
            loadOriginalFiles()
            loadGroups()
            print("✅ 文件已移动到分组: \(group.name ?? "未命名")")
        }
    }

    func moveFiles(_ files: [OriginalFile], to group: FileGroup) {
        if groupManager.moveFiles(files, to: group) {
            loadOriginalFiles()
            loadGroups()
            print("✅ \(files.count)个文件已移动到分组: \(group.name ?? "未命名")")
        }
    }

    // MARK: - 多选模式

    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedFileIDs.removeAll()
        }
    }

    func toggleSelection(_ file: OriginalFile) {
        if selectedFileIDs.contains(file.id) {
            selectedFileIDs.remove(file.id)
        } else {
            selectedFileIDs.insert(file.id)
        }
    }

    // MARK: - 删除功能

    /// 删除单个原始文件
    /// 顺序：先删 Core Data 记录并 save，save 成功后再删磁盘文件。
    /// 这样即使磁盘删除失败也只留下孤立文件（无害），不会出现"磁盘已删、记录还在"的不一致。
    func deleteFile(_ file: OriginalFile) {
        // 先取出属性值：对象删除并保存后属性会变成 nil，再访问非可选属性会崩溃
        let fileID = file.id
        let fileType = file.fileType

        context.delete(file)
        do {
            try context.save()
        } catch {
            context.rollback()
            print("❌ 删除原始文件失败: \(error)")
            errorMessage = error.localizedDescription
            showError = true
            return
        }

        do {
            try StorageManager.shared.deleteOriginal(id: fileID, type: fileType)
        } catch {
            print("❌ 磁盘清理失败 (\(fileID)): \(error)")
        }
        let cacheKey = "original_thumbnail_\(fileID.uuidString)"
        ImageCache.shared.removeImage(forKey: cacheKey)

        loadOriginalFiles()
        loadGroups()

        print("✅ 已删除原始文件: \(fileID)")
    }

    /// 批量删除当前选中的原始文件
    /// 顺序同 deleteFile：先对全部选中对象 delete+save，save 成功后再逐个清理磁盘文件。
    /// save 失败则 rollback，磁盘完全不动。
    func deleteSelectedFiles() {
        let filesToDelete = originalFiles.filter { selectedFileIDs.contains($0.id) }
        guard !filesToDelete.isEmpty else { return }

        // 快照 (id, fileType)：对象删除并保存后不能再读取其属性
        let snapshots = filesToDelete.map { (id: $0.id, type: $0.fileType) }

        for file in filesToDelete {
            context.delete(file)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            print("❌ 保存批量删除结果失败: \(error)")
            errorMessage = error.localizedDescription
            showError = true
            return
        }

        var failedDiskCleanupIDs: [UUID] = []
        for snapshot in snapshots {
            do {
                try StorageManager.shared.deleteOriginal(id: snapshot.id, type: snapshot.type)
            } catch {
                print("❌ 磁盘清理失败 (\(snapshot.id)): \(error)")
                failedDiskCleanupIDs.append(snapshot.id)
            }
            let cacheKey = "original_thumbnail_\(snapshot.id.uuidString)"
            ImageCache.shared.removeImage(forKey: cacheKey)
        }

        print("✅ 已批量删除 \(snapshots.count) 个原始文件")

        if !failedDiskCleanupIDs.isEmpty {
            errorMessage = String(
                format: NSLocalizedString("import.delete.diskCleanupIncomplete", comment: ""),
                failedDiskCleanupIDs.count)
            showError = true
        }

        selectedFileIDs.removeAll()
        isSelectionMode = false
        loadOriginalFiles()
        loadGroups()
    }
}
