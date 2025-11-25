import Combine
import CoreData
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var usedStorageText = "计算中..."
    @Published var fileCount = 0
    @Published var autoLock = false
    @Published var lockTimeout = 300
    @Published var showClearAllAlert = false

    private let context = PersistenceController.shared.container.viewContext

    func loadStorageInfo() {
        let usage = StorageManager.shared.getStorageUsage()
        usedStorageText = formatBytes(usage.totalSize)
        fileCount = usage.fileCount
    }

    func clearAllFiles() {
        let request = NSFetchRequest<OriginalFile>(entityName: "OriginalFile")

        do {
            let files = try context.fetch(request)
            for file in files {
                // 删除加密文件
                try? StorageManager.shared.deleteFile(id: file.id, type: file.fileType)
                // 删除Core Data记录
                context.delete(file)
            }

            try context.save()
            loadStorageInfo()

        } catch {
            print("清空文件失败: \(error)")
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
