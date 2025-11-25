//
//  OriginalImage+CoreDataProperties.swift
//  ZeroNet Redact
//

import CoreData
import Foundation

extension OriginalImage {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OriginalImage> {
        return NSFetchRequest<OriginalImage>(entityName: "OriginalImage")
    }

    @NSManaged public var width: Int64
    @NSManaged public var height: Int64
    @NSManaged public var orientationRaw: Int64

}
