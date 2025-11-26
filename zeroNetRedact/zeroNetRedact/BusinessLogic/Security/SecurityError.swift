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
            return "密码格式无效"
        case .passwordTooShort:
            return "密码至少需要6个字符"
        case .passwordMismatch:
            return "两次输入的密码不一致"
        case .keychainError(let status):
            return "密码存储失败 (错误代码: \(status))"
        case .biometricNotAvailable:
            return "生物识别不可用"
        case .biometricFailed:
            return "生物识别验证失败"
        case .tooManyAttempts(let date):
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.minute, .second]
            formatter.unitsStyle = .full
            let remaining = date.timeIntervalSinceNow
            if remaining > 0, let timeString = formatter.string(from: remaining) {
                return "尝试次数过多，请在 \(timeString) 后重试"
            } else {
                return "尝试次数过多，请稍后重试"
            }
        case .noPasswordSet:
            return "未设置密码"
        case .oldPasswordIncorrect:
            return "原密码不正确"
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
        case .weak: return "弱"
        case .fair: return "中等"
        case .good: return "强"
        case .strong: return "非常强"
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
