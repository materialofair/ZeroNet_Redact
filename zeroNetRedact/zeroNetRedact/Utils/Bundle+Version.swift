//
//  Bundle+Version.swift
//  ZeroNet Redact
//

import Foundation

extension Bundle {
    /// 应用版本号（来自 Info.plist 的 CFBundleShortVersionString，如 "1.1"）
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }
}
