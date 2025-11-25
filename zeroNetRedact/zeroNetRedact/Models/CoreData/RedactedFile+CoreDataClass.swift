//
//  RedactedFile+CoreDataClass.swift
//  ZeroNet Redact
//
//  脱敏文件Core Data实体类 - 代表脱敏处理后的文件（明文存储）
//

import CoreData
import Foundation

@objc(RedactedFile)
public class RedactedFile: NSManagedObject, RedactableFile {

    // MARK: - RedactableFile Protocol

    var fileType: FileType {
        get { FileType(rawValue: fileTypeRaw) ?? .image }
        set { fileTypeRaw = newValue.rawValue }
    }

    // createdAt映射到exportedAt（脱敏文件的创建时间就是导出时间）
    var createdAt: Date {
        get { exportedAt }
        set { exportedAt = newValue }
    }

    // MARK: - Helper Properties

    /// 脱敏文件URL（明文存储）
    var fileURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // 如果路径包含完整的容器路径（/var/mobile/Containers...），直接使用
        if filePath.contains("/Containers/Data/Application/") {
            return URL(fileURLWithPath: filePath)
        }

        // 否则认为是相对路径，拼接Documents目录
        return documentsURL.appendingPathComponent(filePath)
    }

    /// 完整文件路径（自动拼接Documents目录）
    var fullFilePath: String {
        return fileURL.path
    }

    /// 完整缩略图路径（自动拼接Documents目录）
    var fullThumbnailPath: String {
        if thumbnailPath.isEmpty {
            return ""
        }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // 如果路径包含完整的容器路径，直接使用
        if thumbnailPath.contains("/Containers/Data/Application/") {
            return thumbnailPath
        }

        // 否则认为是相对路径，拼接Documents目录
        return documentsURL.appendingPathComponent(thumbnailPath).path
    }

    /// 格式化导出时间
    var formattedExportedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: exportedAt)
    }

    // MARK: - Factory Method

    /// 创建脱敏文件
    static func create(
        in context: NSManagedObjectContext,
        id: UUID,
        fileType: FileType,
        filePath: String,
        fileSize: Int64,
        originalFile: OriginalFile
    ) -> RedactedFile {
        let redacted = RedactedFile(context: context)
        redacted.id = id
        redacted.fileType = fileType
        redacted.filePath = filePath
        redacted.fileSize = fileSize
        redacted.exportedAt = Date()
        redacted.originalFile = originalFile

        return redacted
    }
}
