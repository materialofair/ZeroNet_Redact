import CoreData
import XCTest
@testable import zeroNetRedact

@MainActor
final class RedactedFilePathTests: XCTestCase {
    func testSavedVideoAndThumbnailFollowMigratedApplicationContainer() throws {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let file = RedactedFile(context: context)
        file.filePath = "/var/mobile/Containers/Data/Application/OLD-CONTAINER/Documents/Redacted/Videos/synthetic.mp4"
        file.thumbnailPath = "/var/mobile/Containers/Data/Application/OLD-CONTAINER/Documents/Redacted/Videos/synthetic_thumb.png"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(file.fileURL, documents.appendingPathComponent("Redacted/Videos/synthetic.mp4"))
        XCTAssertEqual(file.fullThumbnailPath, documents.appendingPathComponent("Redacted/Videos/synthetic_thumb.png").path)
    }

    func testLegacySimulatorAndRelativePhotoPathsRemainPortable() {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let file = RedactedFile(context: context)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for stored in ["/Redacted/Images/synthetic.png", "Redacted/Images/synthetic.png", "/Users/test/Library/Developer/CoreSimulator/Devices/DEVICE/data/Containers/Data/Application/OLD/Documents/Redacted/Images/synthetic.png"] {
            file.filePath = stored
            XCTAssertEqual(file.fileURL, documents.appendingPathComponent("Redacted/Images/synthetic.png"))
        }
        file.thumbnailPath = ""
        XCTAssertEqual(file.fullThumbnailPath, "")
    }
}
