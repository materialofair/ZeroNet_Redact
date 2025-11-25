import Combine
import CoreData
import PhotosUI
import SwiftUI

@MainActor
class ImportViewModel: ObservableObject {
    @Published var showPhotosPicker = false
    @Published var showDocumentPicker = false
    @Published var isImporting = false
    @Published var showError = false
    @Published var errorMessage: String?

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

    func importPhotos(_ results: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false }

        do {
            var sources: [ImportSource] = []

            for item in results {
                if let data = try await item.loadTransferable(type: Data.self) {
                    sources.append(.imageData(data))
                }
            }

            let files = try await importManager.batchImport(from: sources)
            print("✅ 成功导入 \(files.count) 个文件")

            // 将导入的文件关联到当前选中的分组
            let targetGroup = selectedGroup ?? defaultGroup
            if let group = targetGroup {
                for file in files {
                    if let originalFile = file as? OriginalFile {
                        _ = groupManager.moveFile(originalFile, to: group)
                    }
                }
                print("📁 文件已关联到分组: \(group.name ?? "未命名")")
            }

            // 重新加载列表
            loadOriginalFiles()

        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func importDocument(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }

        do {
            let file = try await importManager.importFile(from: .fileURL(url))
            print("✅ 成功导入文件: \(file.id)")

            // 将导入的文件关联到当前选中的分组
            let targetGroup = selectedGroup ?? defaultGroup
            if let group = targetGroup,
                let originalFile = file as? OriginalFile
            {
                _ = groupManager.moveFile(originalFile, to: group)
                print("📁 文件已关联到分组: \(group.name ?? "未命名")")
            }

            // 重新加载列表
            loadOriginalFiles()

        } catch {
            errorMessage = error.localizedDescription
            showError = true
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
}
