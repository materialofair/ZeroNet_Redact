//
//  OriginalPDF+CoreDataProperties.swift
//  ZeroNet Redact
//

import CoreData
import Foundation

extension OriginalPDF {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OriginalPDF> {
        return NSFetchRequest<OriginalPDF>(entityName: "OriginalPDF")
    }

    @NSManaged public var pageCount: Int64
    @NSManaged public var title: String
    @NSManaged public var author: String
    @NSManaged public var creator: String
    @NSManaged public var isEncrypted: Bool

}
