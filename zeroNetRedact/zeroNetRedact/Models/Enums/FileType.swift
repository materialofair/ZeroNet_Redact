//
//  FileType.swift
//  ZeroNet Redact
//
//  文件类型枚举 - 支持扩展多种文件格式
//

import Foundation

/// 支持的文件类型枚举
enum FileType: String, Codable {
    case image  // 图片（PNG/JPEG/HEIC）
    case pdf  // PDF文档
    // 未来扩展：
    // case video
    // case document

    /// 显示名称
    var displayName: String {
        switch self {
        case .image: return NSLocalizedString("fileType.image", comment: "")
        case .pdf: return NSLocalizedString("fileType.pdf", comment: "")
        }
    }

    /// 支持的文件扩展名
    var supportedExtensions: [String] {
        switch self {
        case .image: return ["png", "jpg", "jpeg", "heic"]
        case .pdf: return ["pdf"]
        }
    }

    /// 图标
    var icon: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.text"
        }
    }

    /// MIME类型
    var mimeType: String {
        switch self {
        case .image: return "image/*"
        case .pdf: return "application/pdf"
        }
    }
}
