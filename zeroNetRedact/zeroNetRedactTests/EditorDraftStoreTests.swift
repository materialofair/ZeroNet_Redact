import CoreData
import UIKit
import PDFKit
import XCTest
@testable import zeroNetRedact

@MainActor
final class EditorDraftStoreTests: XCTestCase {
    private var directory: URL!
    private var store: EditorDraftStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = EditorDraftStore(directory: directory)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }
    private func draft(id: UUID = UUID()) throws -> EditorDraft {
        EditorDraft(originalID: id, masks: [DraftMask(bounds: CGRect(x: 3, y: 5, width: 9, height: 12), page: 2,
                    effect: try DraftEffect(.rectangle(color: .purple, opacity: 0.7)))], pageIndex: 2,
                    recognition: [], selectedEffect: try DraftEffect(.blur(radius: 12)))
    }
    func testEncryptedRoundTripAndTamperRejection() throws {
        let draft = try draft()
        try store.save(draft, session: store.beginSession(for: draft.originalID))
        var bytes = try Data(contentsOf: store.url(for: draft.originalID))
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: bytes))
        let restored = try XCTUnwrap(store.load(id: draft.originalID))
        XCTAssertEqual(restored.masks[0].bounds, draft.masks[0].bounds)
        XCTAssertEqual(try restored.masks[0].effect.restored(), try draft.masks[0].effect.restored())
        XCTAssertEqual(restored.pageIndex, 2)
        bytes[bytes.count / 2] ^= 0xff
        try bytes.write(to: store.url(for: draft.originalID))
        XCTAssertThrowsError(try store.load(id: draft.originalID))
    }

    func testVideoSettingsAndTimelineRoundTripAndRejectInvalidTime() throws {
        var value = try draft()
        let timeline = VideoFaceTimeline(frames: [VideoFaceFrame(seconds: 1.5,
            normalizedRects: [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3)])],
            frameRate: 30, totalUniqueFaces: 1)
        value.videoState = DraftVideoState(sticker: .orangeSmiley, voice: .original,
                                           timeline: timeline, playbackSeconds: 2.5)
        let session = store.beginSession(for: value.originalID)
        try store.save(value, session: session)
        let state = try XCTUnwrap(store.load(id: value.originalID)?.videoState)
        XCTAssertEqual(state.playbackSeconds, 2.5)
        XCTAssertEqual(state.timeline?.frames.first?.seconds, 1.5)
        XCTAssertEqual(state.timeline?.totalUniqueFaces, 1)
        value.videoState?.frameRate = -1
        XCTAssertThrowsError(try store.save(value, session: session))
    }
    func testDeleteRevokesQueuedSaveAndNewSessionCanSave() throws {
        let draft = try draft()
        let session = store.beginSession(for: draft.originalID)
        try store.save(draft, session: session)
        try store.delete(id: draft.originalID)
        try store.save(draft, session: session)
        XCTAssertNil(try store.load(id: draft.originalID))
        try store.save(draft, session: store.beginSession(for: draft.originalID))
        XCTAssertNotNil(try store.load(id: draft.originalID))
    }
    func testNewSessionRevokesOldEditor() throws {
        let draft = try draft()
        let old = store.beginSession(for: draft.originalID)
        _ = store.beginSession(for: draft.originalID)
        try store.save(draft, session: old)
        XCTAssertNil(try store.load(id: draft.originalID))
    }

    func testBatchScopesPreserveIndependentReviewDecisionsAndDeleteWithOriginal() throws {
        let id = UUID(), first = UUID(), second = UUID()
        var regular = try draft(id: id)
        var batchA = try draft(id: id)
        var batchB = try draft(id: id)
        batchA.scopeID = first; batchB.scopeID = second
        regular.pageIndex = 1; batchA.pageIndex = 2; batchB.pageIndex = 3
        batchA.recognition = [] // Explicitly ignored candidates must remain ignored on reopen.
        let regularSession = store.beginSession(for: id)
        let aSession = store.beginSession(for: id, scope: first)
        let bSession = store.beginSession(for: id, scope: second)
        try store.save(regular, session: regularSession)
        try store.save(batchA, session: aSession)
        try store.save(batchB, session: bSession)
        XCTAssertEqual(try store.load(id: id)?.pageIndex, 1)
        XCTAssertEqual(try store.load(id: id, scope: first)?.pageIndex, 2)
        XCTAssertEqual(try store.load(id: id, scope: first)?.recognition.count, 0)
        try store.delete(id: id, scope: first)
        XCTAssertNil(try store.load(id: id, scope: first))
        XCTAssertNotNil(try store.load(id: id))
        XCTAssertEqual(try store.load(id: id, scope: second)?.pageIndex, 3)
        try store.deleteAll(id: id)
        try store.save(regular, session: regularSession)
        try store.save(batchA, session: aSession)
        try store.save(batchB, session: bSession)
        XCTAssertNil(try store.load(id: id))
        XCTAssertNil(try store.load(id: id, scope: first))
        XCTAssertNil(try store.load(id: id, scope: second))
    }
    func testOriginalDeletionRemovesDraft() throws {
        let draft = try draft()
        let shared = EditorDraftStore.shared
        defer { try? shared.delete(id: draft.originalID) }
        try shared.save(draft, session: shared.beginSession(for: draft.originalID))
        try StorageManager.shared.deleteOriginal(id: draft.originalID, type: .image)
        XCTAssertNil(try shared.load(id: draft.originalID))
    }
    func testImageRestorePreservesRenderedEffectsAndRotatedBase() async throws {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let original = OriginalImage(context: context)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
        let first = ImageRedactionEditor(file: original)
        first.loadForTesting(image: image)
        first.replaceOriginalImage(with: try XCTUnwrap(image.rotated(by: .pi / 2)))
        first.applyRedaction(at: CGRect(x: 2, y: 4, width: 10, height: 15), effect: .rectangle(color: .red, opacity: 0.8))
        await first.waitForPendingRender()
        let (base, masks) = try first.draftState()
        XCTAssertNotNil(base)
        let draft = EditorDraft(originalID: UUID(), replacementImage: base, replacementScale: first.draftImageScale, masks: masks, pageIndex: 0,
                                recognition: [], selectedEffect: try DraftEffect(.solidBlack))
        let second = ImageRedactionEditor(file: original)
        second.loadForTesting(image: image)
        try second.restoreDraft(draft)
        await second.waitForPendingRender()
        XCTAssertEqual(second.currentImage?.size, first.currentImage?.size)
        XCTAssertEqual(second.currentImage?.pngData(), first.currentImage?.pngData())
        XCTAssertTrue(second.canUndo)
    }
    func testPDFRestorePreservesPagesColorsAndAtomicUndo() async throws {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let file = OriginalPDF(context: context)
        file.id = UUID()
        let document = PDFDocument()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 1)
        let storage = StorageManager.shared
        defer { try? storage.deleteOriginal(id: file.id, type: .pdf) }
        _ = try storage.saveEncryptedOriginal(data: CryptoEngine.shared.encrypt(data: XCTUnwrap(document.dataRepresentation())), id: file.id, type: .pdf)
        let first = PDFRedactionEditor(file: file)
        try await first.loadFile(file)
        let regions = [0, 1].map { SensitiveRegion(type: .phoneNumber, boundingBox: CGRect(x: 2, y: 3, width: 10, height: 10), confidence: 1, pageIndex: $0) }
        XCTAssertEqual(first.applyRedactionsByPage(regions, effect: .rectangle(color: .red, opacity: 1)).count, 2)
        first.goToPage(1)
        let draft = EditorDraft(originalID: file.id, masks: try first.draftMasks(), pageIndex: 1,
                                recognition: regions.map(DraftRecognition.init), selectedEffect: try DraftEffect(.solidBlack))
        first.undo()
        XCTAssertTrue(try first.draftMasks().isEmpty)
        let second = PDFRedactionEditor(file: file)
        try await second.loadFile(file)
        try second.restoreDraft(draft)
        XCTAssertEqual(second.currentPageIndex, 1)
        XCTAssertEqual(try second.draftMasks().count, 2)
        XCTAssertEqual(second.redactionAnnotations[1]?.first?.interiorColor, .red)
        XCTAssertEqual(draft.recognition.map(\.region).count, 2)
    }

    func testInvalidGeometryIsRejected() throws {
        var draft = try draft()
        draft.masks[0].bounds.size.width = -1
        XCTAssertThrowsError(try store.save(draft, session: store.beginSession(for: draft.originalID)))
    }

    func testEveryEffectRoundTrips() throws {
        for effect: RedactionEffect in [.solidBlack, .mosaic(pixelSize: 24), .blur(radius: 7.5),
                                       .rectangle(color: .cyan, opacity: 0.4), .faceSticker(.orangeSmiley)] {
            let payload = try JSONEncoder().encode(DraftEffect(effect))
            XCTAssertEqual(try JSONDecoder().decode(DraftEffect.self, from: payload).restored(), effect)
        }
    }
}
