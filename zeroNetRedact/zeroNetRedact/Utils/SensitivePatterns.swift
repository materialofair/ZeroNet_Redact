//
//  SensitivePatterns.swift
//  ZeroNet Redact
//
//  敏感信息正则表达式模式
//

import Foundation

/// 敏感信息检测模式
struct SensitivePatterns {

    /// 中国大陆手机号：1开头的11位数字 (支持空格/连字符分隔)
    static let phoneNumber = #"1[3-9]\d[\s\-]?\d{4}[\s\-]?\d{4}|1[3-9]\d{9}"#

    /// 邮箱地址
    static let email = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}"#

    /// 中国大陆身份证号：18位或15位 (支持空格分隔,更宽松的匹配)
    static let idCard =
        #"[1-9]\d{5}[\s]?(?:18|19|20)?\d{2}[\s]?(?:0[1-9]|1[0-2])[\s]?(?:0[1-9]|[12]\d|3[01])[\s]?\d{3}[\s]?[\dXx]?|[1-9]\d{5}(?:18|19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx]|[1-9]\d{7}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}"#

    /// 银行卡号：13-19位数字 (支持空格/连字符分隔)
    static let bankCard = #"\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4,7}|\d{13,19}"#

    /// IP地址
    static let ipAddress = #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#

    /// 车牌号（中国）
    static let licensePlate =
        #"[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼使领][A-Z][A-HJ-NP-Z0-9]{4,5}[A-HJ-NP-Z0-9挂学警港澳]"#

    /// 护照号（中国）
    static let passport = #"[EG]\d{8}"#

    /// URL
    static let url = #"https?://[^\s/$.?#].[^\s]*"#

    // MARK: - 验证方法

    /// 验证是否匹配模式
    static func matches(text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// 查找所有匹配项
    static func findMatches(in text: String, pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range)
    }
}
