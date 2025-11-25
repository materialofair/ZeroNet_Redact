//
//  RedactableFile.swift
//  ZeroNet Redact
//
//  可脱敏文件协议 - 支持原始文件和脱敏文件的统一抽象
//

import Foundation

/// 可脱敏文件协议 - 统一OriginalFile和RedactedFile的接口
protocol RedactableFile: AnyObject, Identifiable {
    /// 唯一标识符
    var id: UUID { get }

    /// 文件类型
    var fileType: FileType { get }

    /// 创建时间
    var createdAt: Date { get }

    /// 文件大小（字节）
    var fileSize: Int64 { get }
}

/// 可脱敏文件的扩展方法
extension RedactableFile {
    /// 格式化文件大小
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// 格式化创建时间
    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
