import Combine
import Foundation
import SwiftUI

/// 认证视图模型 - 用于密码验证界面
@MainActor
class AuthenticationViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var passwordInput = ""
    @Published var showPassword = false
    @Published var isVerifying = false
    @Published var errorMessage: String?
    @Published var remainingAttempts = 5
    @Published var lockoutEndTime: Date?

    // MARK: - Private Properties

    private let passwordManager = PasswordManager.shared
    private let biometricManager = BiometricAuthManager.shared

    // MARK: - Computed Properties

    var isBiometricAvailable: Bool {
        biometricManager.isBiometricAvailable() && AppState.shared.biometricEnabled
    }

    var biometricType: BiometricType {
        biometricManager.biometricType()
    }

    var biometricTypeText: String {
        biometricType.displayName
    }

    var biometricIcon: String {
        biometricType.iconName
    }

    // MARK: - Initialization

    init() {
        updateRemainingAttempts()
        checkLockout()
    }

    // MARK: - Public Methods

    /// 验证密码
    func verifyPassword() async -> Bool {
        guard !passwordInput.isEmpty else {
            errorMessage = "请输入密码"
            return false
        }

        // 检查是否被锁定
        let (locked, endTime) = passwordManager.isLocked()
        if locked, let endTime = endTime {
            lockoutEndTime = endTime
            errorMessage = SecurityError.tooManyAttempts(retryAfter: endTime).localizedDescription
            return false
        }

        isVerifying = true
        errorMessage = nil

        // 模拟网络延迟，提供更好的用户体验
        try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2秒

        let isValid = passwordManager.verifyPassword(passwordInput)

        isVerifying = false

        if isValid {
            // 验证成功
            errorMessage = nil
            AppState.shared.unlockApp()
            passwordInput = ""  // 立即清除密码
            return true
        } else {
            // 验证失败
            passwordManager.recordFailedAttempt()
            updateRemainingAttempts()

            let attempts = remainingAttempts
            if attempts > 0 {
                errorMessage = "密码错误，还剩 \(attempts) 次尝试"
            } else {
                checkLockout()
            }

            passwordInput = ""  // 清除错误的密码
            return false
        }
    }

    /// 使用生物识别认证
    func authenticateWithBiometric() async -> Bool {
        guard isBiometricAvailable else {
            errorMessage = "生物识别不可用"
            return false
        }

        isVerifying = true
        errorMessage = nil

        do {
            let success = try await biometricManager.authenticate(
                reason: "解锁 ZeroNet Redact"
            )

            isVerifying = false

            if success {
                AppState.shared.unlockApp()
                return true
            } else {
                // 用户取消或选择使用密码
                return false
            }
        } catch {
            isVerifying = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Private Methods

    private func updateRemainingAttempts() {
        remainingAttempts = passwordManager.getRemainingAttempts()
    }

    private func checkLockout() {
        let (locked, endTime) = passwordManager.isLocked()
        if locked, let endTime = endTime {
            lockoutEndTime = endTime
            errorMessage = SecurityError.tooManyAttempts(retryAfter: endTime).localizedDescription
        } else {
            lockoutEndTime = nil
        }
    }
}

/// 密码设置视图模型 - 用于首次设置和修改密码
@MainActor
class PasswordSetupViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var showPassword = false
    @Published var enableBiometric = true
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let passwordManager = PasswordManager.shared
    private let biometricManager = BiometricAuthManager.shared

    // MARK: - Computed Properties

    var passwordStrength: PasswordStrength {
        passwordManager.evaluateStrength(password)
    }

    var passwordsMatch: Bool {
        !confirmPassword.isEmpty && password == confirmPassword
    }

    var hasLettersAndNumbers: Bool {
        password.contains(where: { $0.isLetter }) && password.contains(where: { $0.isNumber })
    }

    var canSubmit: Bool {
        password.count >= 6 && passwordsMatch
    }

    var isBiometricAvailable: Bool {
        biometricManager.isBiometricAvailable()
    }

    var biometricType: BiometricType {
        biometricManager.biometricType()
    }

    var biometricTypeText: String {
        biometricType.displayName
    }

    var biometricIcon: String {
        biometricType.iconName
    }

    // MARK: - Public Methods

    /// 设置密码
    func setupPassword() async -> Bool {
        guard canSubmit else {
            errorMessage = "请检查密码输入"
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            try passwordManager.setPassword(password)

            // 保存设置
            AppState.shared.passwordEnabled = true
            AppState.shared.biometricEnabled = enableBiometric
            AppState.shared.isFirstLaunch = false
            AppState.shared.unlockApp()

            // 清除密码
            password = ""
            confirmPassword = ""

            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    /// 跳过设置
    func skipSetup() {
        AppState.shared.isFirstLaunch = false
        AppState.shared.passwordEnabled = false
        AppState.shared.unlockApp()
    }

    /// 修改密码
    func changePassword(oldPassword: String) async -> Bool {
        guard canSubmit else {
            errorMessage = "请检查密码输入"
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            try passwordManager.changePassword(oldPassword: oldPassword, newPassword: password)

            // 清除密码
            password = ""
            confirmPassword = ""

            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}
