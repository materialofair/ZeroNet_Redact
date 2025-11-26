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

    // MARK: - 密码保护相关
    @Published var passwordProtectionEnabled = false
    @Published var showPasswordSetup = false
    @Published var showChangePassword = false
    @Published var showDisablePasswordAlert = false
    @Published var biometricEnabled = true
    @Published var isBiometricAvailable = false
    @Published var biometricTypeText = ""
    @Published var biometricIcon = ""

    private let context = PersistenceController.shared.container.viewContext
    private let passwordManager = PasswordManager.shared
    private let biometricManager = BiometricAuthManager.shared

    init() {
        loadSettings()
        checkBiometricAvailability()
    }

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

    // MARK: - 密码保护方法

    private func loadSettings() {
        // 从 AppState 加载设置
        passwordProtectionEnabled = AppState.shared.passwordEnabled
        biometricEnabled = AppState.shared.biometricEnabled
    }

    private func checkBiometricAvailability() {
        isBiometricAvailable = biometricManager.isBiometricAvailable()

        let type = biometricManager.biometricType()
        biometricTypeText = type.displayName
        biometricIcon = type.iconName
    }

    func disablePasswordProtection() {
        do {
            try passwordManager.removePassword()
            AppState.shared.passwordEnabled = false
            passwordProtectionEnabled = false
        } catch {
            print("禁用密码保护失败: \(error)")
        }
    }

    func updateBiometricSetting(_ enabled: Bool) {
        AppState.shared.biometricEnabled = enabled
        biometricEnabled = enabled
    }
}
