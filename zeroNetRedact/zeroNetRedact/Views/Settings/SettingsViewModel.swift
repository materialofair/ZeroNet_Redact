import Combine
import CoreData
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var usedStorageText = NSLocalizedString("common.calculating", comment: "")
    @Published var fileCount = 0
    @Published var autoLock = false
    @Published var lockTimeout = 300

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
