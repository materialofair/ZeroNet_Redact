//
//  RedactedFile+CoreDataProperties.swift
//  ZeroNet Redact
//
//  脱敏文件Core Data属性
//

import CoreData
import Foundation

extension RedactedFile {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RedactedFile> {
        return NSFetchRequest<RedactedFile>(entityName: "RedactedFile")
    }

    @NSManaged public var id: UUID
    @NSManaged public var fileTypeRaw: String
    @NSManaged public var filePath: String
    @NSManaged public var thumbnailPath: String
    @NSManaged public var fileSize: Int64
    @NSManaged public var exportedAt: Date
    @NSManaged public var group: FileGroup?
    @NSManaged public var originalFile: OriginalFile?
}
