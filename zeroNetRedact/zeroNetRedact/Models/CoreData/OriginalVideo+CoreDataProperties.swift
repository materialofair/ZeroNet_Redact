import CoreData
import Foundation

extension OriginalVideo {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<OriginalVideo> {
        NSFetchRequest<OriginalVideo>(entityName: "OriginalVideo")
    }

    @NSManaged public var duration: Double
    @NSManaged public var width: Int64
    @NSManaged public var height: Int64
    @NSManaged public var nominalFrameRate: Double
    @NSManaged public var hasAudio: Bool
}
