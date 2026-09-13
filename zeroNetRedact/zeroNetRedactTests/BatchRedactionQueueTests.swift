import CoreData
import XCTest
@testable import zeroNetRedact

@MainActor
final class BatchRedactionQueueTests: XCTestCase {
    func testRecipeKeyIncludesRulesAndDeduplicatesContent() {
        let recipe = BatchRecipe(types: [.email, .phoneNumber], keyword: "Acme")
        XCTAssertEqual(recipe.fingerprint, BatchRecipe(types: [.phoneNumber, .email], keyword: "Acme").fingerprint)
        XCTAssertNotEqual(recipe.fingerprint, BatchRecipe(types: [.email], keyword: "Acme").fingerprint)
        XCTAssertNotEqual(recipe.fingerprint, BatchRecipe(types: [.email, .phoneNumber], keyword: "Other").fingerprint)
        let job = BatchJob(recipe: recipe, sources: [(UUID(), "hash-a"), (UUID(), "hash-a"), (UUID(), "hash-b")])
        XCTAssertEqual(job.items.count, 2)
        XCTAssertNotEqual(job.items[0].exportID, job.items[1].exportID)
    }

    func testRestartRecoversInterruptedItemAndCommittedExport() throws {
        var job = BatchJob(recipe: .init(types: [.email], keyword: ""), sources: (0..<4).map { (UUID(), "hash-\($0)") })
        job.items[0].state = .analyzing
        job.items[1].state = .review
        job.items[2].state = .failed
        job.items[3].state = .succeeded
        let exportID = job.items[1].exportID
        var decoded = try JSONDecoder().decode(BatchJob.self, from: JSONEncoder().encode(job))
        decoded.recover(completed: [exportID])
        XCTAssertEqual(decoded.items.map(\.state), [.waiting, .succeeded, .failed, .succeeded])
        XCTAssertEqual(decoded.items[1].exportID, exportID)
    }

    func testEncryptedQueueResumeAndCorruptFileNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var job = BatchJob(recipe: .init(types: [.email], keyword: "Confidential"), sources: [(UUID(), "hash")])
        job.items[0].state = .analyzing
        let data = try CryptoEngine.shared.encrypt(data: JSONEncoder().encode(job))
        try data.write(to: url)
        let queue = BatchRedactionQueue(url: url)
        XCTAssertEqual(queue.job?.items.first?.state, .waiting)
        XCTAssertNil(try Data(contentsOf: url).range(of: Data("Confidential".utf8)))
        let corrupt = Data([0, 1, 2])
        try corrupt.write(to: url)
        let broken = BatchRedactionQueue(url: url)
        XCTAssertNotNil(broken.error)
        broken.create(recipe: .init(types: [.email], keyword: ""), files: [])
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testOnlyDurableExportCompletesQueueAndRetryReusesExistingOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let job = BatchJob(recipe: .init(types: [.email], keyword: ""), sources: [(UUID(), "hash")])
        let item = job.items[0]
        let queueURL = directory.appendingPathComponent("queue.enc")
        try CryptoEngine.shared.encrypt(data: JSONEncoder().encode(job)).write(to: queueURL)
        let context = PersistenceController.shared.container.viewContext
        let source = OriginalImage(context: context)
        source.id = item.originalID; source.fileTypeRaw = FileType.image.rawValue
        source.createdAt = Date(); source.encryptedDataPath = ""; source.encryptedThumbnailPath = ""
        let record = RedactedFile(context: context)
        record.originalFile = source
        record.id = item.exportID
        record.fileTypeRaw = FileType.image.rawValue
        let output = try StorageManager.shared.saveRedactedFile(data: Data([1, 2, 3]), id: item.exportID, type: .image)
        let thumbnail = try StorageManager.shared.saveRedactedThumbnail(data: Data([1, 2, 3]), id: item.exportID, type: .image)
        record.filePath = output.path
        record.thumbnailPath = thumbnail.path
        record.fileSize = 3
        record.exportedAt = Date()
        defer {
            context.delete(record)
            context.delete(source)
            try? context.save()
            try? StorageManager.shared.deleteRedacted(id: item.exportID, type: .image)
        }
        XCTAssertNotEqual(BatchRedactionQueue(url: queueURL).job?.items[0].state, .succeeded)
        try context.save()
        XCTAssertEqual(BatchRedactionQueue(url: queueURL).job?.items[0].state, .succeeded)
        let editor = EditorViewModel(file: source)
        editor.batchExportID = item.exportID
        let first = await editor.exportFile()
        let retry = await editor.exportFile()
        XCTAssertTrue(first)
        XCTAssertTrue(retry)
        XCTAssertEqual(editor.exportedFileURL, output)
        let request = RedactedFile.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", item.exportID as CVarArg)
        XCTAssertEqual(try context.count(for: request), 1)
    }
}
