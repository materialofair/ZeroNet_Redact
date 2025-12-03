import Foundation

/// 安全相关错误类型
enum SecurityError: LocalizedError {
    case invalidPassword
    case passwordTooShort
    case passwordMismatch
    case keychainError(OSStatus)
    case biometricNotAvailable
    case biometricFailed
    case tooManyAttempts(retryAfter: Date)
    case noPasswordSet
    case oldPasswordIncorrect

    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return NSLocalizedString("security.error.invalidPassword", comment: "")
        case .passwordTooShort:
            return NSLocalizedString("security.error.passwordTooShort", comment: "")
        case .passwordMismatch:
            return NSLocalizedString("security.error.passwordMismatch", comment: "")
        case .keychainError(let status):
            return String(
                format: NSLocalizedString("security.error.keychainError", comment: ""), status)
        case .biometricNotAvailable:
            return NSLocalizedString("security.error.biometricNotAvailable", comment: "")
        case .biometricFailed:
            return NSLocalizedString("security.error.biometricFailed", comment: "")
        case .tooManyAttempts(let date):
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.minute, .second]
            formatter.unitsStyle = .full
            let remaining = date.timeIntervalSinceNow
            if remaining > 0, let timeString = formatter.string(from: remaining) {
                return String(
                    format: NSLocalizedString(
                        "security.error.tooManyAttemptsWithTime", comment: ""), timeString)
            } else {
                return NSLocalizedString("security.error.tooManyAttempts", comment: "")
            }
        case .noPasswordSet:
            return NSLocalizedString("security.error.noPasswordSet", comment: "")
        case .oldPasswordIncorrect:
            return NSLocalizedString("security.error.oldPasswordIncorrect", comment: "")
        }
    }
}

/// 密码强度等级
enum PasswordStrength {
    case weak  // < 6 chars
    case fair  // 6-11 chars
    case good  // 12+ chars + numbers or special
    case strong  // 15+ chars + upper + number + special

    var description: String {
        switch self {
        case .weak: return NSLocalizedString("password.strength.weak", comment: "")
        case .fair: return NSLocalizedString("password.strength.fair", comment: "")
        case .good: return NSLocalizedString("password.strength.good", comment: "")
        case .strong: return NSLocalizedString("password.strength.strong", comment: "")
        }
    }

    var color: String {
        switch self {
        case .weak: return "dangerRed"
        case .fair: return "warningOrange"
        case .good: return "successMint"
        case .strong: return "successGreen"
        }
    }
}

/// 生物识别类型
enum BiometricType {
    case none
    case touchID
    case faceID

    var displayName: String {
        switch self {
        case .none: return ""
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        }
    }

    var iconName: String {
        switch self {
        case .none: return ""
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        }
    }
}
