import Combine
import CoreData
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var usedStorageText = NSLocalizedString("common.calculating", comment: "")
    @Published var fileCount = 0
    /// 自动锁定：持久化于 AppState（@AppStorage），此处保持 @Published 供 UI 绑定
    @Published var autoLock = false {
        didSet {
            guard autoLock != AppState.shared.autoLockEnabled else { return }
            AppState.shared.autoLockEnabled = autoLock
        }
    }
    /// 自动锁定超时（秒），0 表示立即
    @Published var lockTimeout = 60 {
        didSet {
            guard lockTimeout != AppState.shared.autoLockTimeout else { return }
            AppState.shared.autoLockTimeout = lockTimeout
        }
    }

    // MARK: - 密码保护相关
    @Published var passwordProtectionEnabled = false
    @Published var showPasswordSetup = false
    @Published var showChangePassword = false
    @Published var showDisablePasswordAlert = false
    @Published var showDisablePasswordError = false
    @Published var disablePasswordErrorMessage: String?
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
        autoLock = AppState.shared.autoLockEnabled
        lockTimeout = AppState.shared.autoLockTimeout
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
            // 回滚 UI 状态：密码仍启用，开关恢复打开，避免"显示关闭、实际仍锁屏"的不一致
            passwordProtectionEnabled = true
            disablePasswordErrorMessage = error.localizedDescription
            showDisablePasswordError = true
        }
    }

    func updateBiometricSetting(_ enabled: Bool) {
        AppState.shared.biometricEnabled = enabled
        biometricEnabled = enabled
    }
}
