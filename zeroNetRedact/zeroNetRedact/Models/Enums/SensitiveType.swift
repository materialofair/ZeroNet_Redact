//
//  SensitiveType.swift
//  ZeroNet Redact
//
//  敏感信息类型枚举
//

import Foundation

/// 敏感信息类型
enum SensitiveType: String, Codable {
    case phoneNumber = "phone"  // 手机号
    case email = "email"  // 邮箱
    case idCard = "id_card"  // 身份证
    case bankCard = "bank_card"  // 银行卡
    case custom = "custom"  // 自定义

    /// 显示名称
    var displayName: String {
        switch self {
        case .phoneNumber: return NSLocalizedString("sensitiveType.phoneNumber", comment: "")
        case .email: return NSLocalizedString("sensitiveType.email", comment: "")
        case .idCard: return NSLocalizedString("sensitiveType.idCard", comment: "")
        case .bankCard: return NSLocalizedString("sensitiveType.bankCard", comment: "")
        case .custom: return NSLocalizedString("sensitiveType.custom", comment: "")
        }
    }

    /// Emoji图标
    var emoji: String {
        switch self {
        case .phoneNumber: return "📱"
        case .email: return "📧"
        case .idCard: return "🆔"
        case .bankCard: return "💳"
        case .custom: return "🔒"
        }
    }

    /// SF Symbol图标
    var icon: String {
        switch self {
        case .phoneNumber: return "phone.fill"
        case .email: return "envelope.fill"
        case .idCard: return "person.text.rectangle"
        case .bankCard: return "creditcard.fill"
        case .custom: return "lock.fill"
        }
    }
}
