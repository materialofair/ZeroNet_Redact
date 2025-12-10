//
//  OriginalFile+CoreDataProperties.swift
//  ZeroNet Redact
//
//  原始文件Core Data属性
//

import CoreData
import Foundation

extension OriginalFile {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OriginalFile> {
        return NSFetchRequest<OriginalFile>(entityName: "OriginalFile")
    }

    @NSManaged public var id: UUID
    @NSManaged public var fileTypeRaw: String
    @NSManaged public var encryptedDataPath: String
    @NSManaged public var encryptedThumbnailPath: String
    @NSManaged public var createdAt: Date
    @NSManaged public var fileSize: Int64
    @NSManaged public var metadataJSON: String?
    @NSManaged public var contentHash: String?
    @NSManaged public var group: FileGroup?
    @NSManaged public var redactedVersions: NSSet?
}

// MARK: - Generated accessors for redactedVersions
extension OriginalFile {

    @objc(addRedactedVersionsObject:)
    @NSManaged public func addToRedactedVersions(_ value: RedactedFile)

    @objc(removeRedactedVersionsObject:)
    @NSManaged public func removeFromRedactedVersions(_ value: RedactedFile)

    @objc(addRedactedVersions:)
    @NSManaged public func addToRedactedVersions(_ values: NSSet)

    @objc(removeRedactedVersions:)
    @NSManaged public func removeFromRedactedVersions(_ values: NSSet)
}
