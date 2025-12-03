import Foundation
import LocalAuthentication

/// 生物识别认证管理器 - 负责 Face ID / Touch ID
class BiometricAuthManager {
    static let shared = BiometricAuthManager()

    private init() {}

    // MARK: - Public Methods

    /// 检查生物识别是否可用
    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?

        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 获取生物识别类型
    func biometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    /// 执行生物识别认证
    /// - Parameter reason: 提示用户的原因文本
    /// - Returns: 认证是否成功
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()

        // 设置取消按钮文本
        context.localizedCancelTitle = NSLocalizedString("biometric.usePassword", comment: "")

        // 检查是否可用
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        else {
            if let error = error {
                throw error
            }
            throw SecurityError.biometricNotAvailable
        }

        // 执行认证
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch let error as LAError {
            // 处理各种错误情况
            switch error.code {
            case .userCancel, .userFallback, .systemCancel:
                // 用户取消或选择使用密码，不抛出错误
                return false
            case .biometryNotAvailable, .biometryNotEnrolled:
                throw SecurityError.biometricNotAvailable
            case .authenticationFailed:
                throw SecurityError.biometricFailed
            default:
                throw error
            }
        } catch {
            throw error
        }
    }

    /// 使用生物识别或密码认证（降级选项）
    /// - Parameter reason: 提示用户的原因文本
    /// - Returns: 认证是否成功
    func authenticateWithFallback(reason: String) async throws -> Bool {
        let context = LAContext()

        // 设置取消按钮文本
        context.localizedCancelTitle = NSLocalizedString("common.cancel", comment: "")
        context.localizedFallbackTitle = NSLocalizedString("biometric.usePassword", comment: "")

        // 检查是否可用（包括密码作为降级选项）
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error = error {
                throw error
            }
            throw SecurityError.biometricNotAvailable
        }

        // 执行认证
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel:
                return false
            default:
                throw error
            }
        } catch {
            throw error
        }
    }
}
