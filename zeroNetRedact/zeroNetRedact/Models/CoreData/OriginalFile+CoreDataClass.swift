//
//  OriginalFile+CoreDataClass.swift
//  ZeroNet Redact
//
//  原始文件Core Data实体类 - 代表用户导入的原始文件（加密存储）
//

import CoreData
import Foundation

@objc(OriginalFile)
public class OriginalFile: NSManagedObject, RedactableFile {

    // MARK: - RedactableFile Protocol

    var fileType: FileType {
        get { FileType(rawValue: fileTypeRaw) ?? .image }
        set { fileTypeRaw = newValue.rawValue }
    }

    // MARK: - Helper Methods

    /// 设置元数据
    func setMetadata(_ metadata: [String: Any]) {
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            self.metadataJSON = jsonString
        }
    }

    /// 获取元数据
    var typeSpecificMetadata: [String: Any] {
        guard let json = metadataJSON,
            let data = json.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return dict
    }

    /// 获取加密原文件URL
    var encryptedFileURL: URL {
        return URL(fileURLWithPath: encryptedDataPath)
    }

    /// 获取加密缩略图URL
    var thumbnailURL: URL {
        return URL(fileURLWithPath: encryptedThumbnailPath)
    }

    /// 获取所有脱敏版本（按时间倒序）
    var redactedVersionsArray: [RedactedFile] {
        let set = redactedVersions as? Set<RedactedFile> ?? []
        return set.sorted { $0.exportedAt > $1.exportedAt }
    }

    /// 最新的脱敏版本
    var latestRedactedVersion: RedactedFile? {
        return redactedVersionsArray.first
    }
}
