//
//  FileWrapper.swift
//  ZeroNet Redact
//
//  文件包装器 - 解决协议类型无法在sheet中传递的问题
//

import Foundation

/// 文件包装器 - 将协议类型包装成具体类型
struct FileWrapper: Identifiable {
    let id = UUID()
    let file: RedactableFile

    init(_ file: RedactableFile) {
        self.file = file
    }
}
