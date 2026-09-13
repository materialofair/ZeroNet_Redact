import XCTest
import CoreData
@testable import zeroNetRedact

final class VideoManualRegionTests: XCTestCase {
    @MainActor
    func testPlaybackTimeUpdatesReviewWithoutOverwritingActiveScrub() throws {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let video = OriginalVideo(context: context)
        video.duration = 3
        let model = VideoEditorViewModel(video: video)
        model.synchronizeReviewTime(1.5)
        XCTAssertEqual(model.reviewSeconds, 1.5)
        model.reviewScrubbingChanged(true)
        model.synchronizeReviewTime(2)
        XCTAssertEqual(model.reviewSeconds, 1.5)
        model.reviewScrubbingChanged(false)
        model.synchronizeReviewTime(2)
        XCTAssertEqual(model.reviewSeconds, 2)
        model.synchronizeReviewTime(.nan)
        XCTAssertEqual(model.reviewSeconds, 2)
    }
    func testRedrawKeepsIdentityIntervalAndEffectWithoutMutatingOriginal() throws {
        let originalRect = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        var original = try XCTUnwrap(VideoManualRegion(rect: originalRect, start: 1, end: 2, duration: 3))
        original.effect = VideoRedactionSticker.blueSmiley.rawValue
        let replacement = CGRect(x: 0.4, y: 0.4, width: 0.3, height: 0.3)
        let candidate = try XCTUnwrap(original.redrawing(rect: replacement, duration: 3))
        XCTAssertEqual(candidate.id, original.id)
        XCTAssertEqual(candidate.start, 1)
        XCTAssertEqual(candidate.end, 2)
        XCTAssertEqual(candidate.effect, original.effect)
        XCTAssertEqual(candidate.rect, replacement)
        XCTAssertEqual(original.rect, originalRect)
    }
    @MainActor
    func testEncryptedDraftSurvivesNewStoreWithManualIntervalsAndGroups() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let rect = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        let region = try XCTUnwrap(VideoManualRegion(rect: rect, start: 1, end: 2, duration: 3))
        let timeline = VideoFaceTimeline(frames: [VideoFaceFrame(seconds: 1, normalizedRects: [rect], trackIDs: [7])], frameRate: 30, totalUniqueFaces: 1)
        var state = DraftVideoState(sticker: .orangeSmiley, voice: .mute, timeline: timeline, playbackSeconds: 1)
        state.manualRegions = [region]
        state.groups = [VideoPersonGroup(trackIDs: [7, 8], effect: "blur")]
        let draft = EditorDraft(originalID: UUID(), masks: [], pageIndex: 0, recognition: [], selectedEffect: try DraftEffect(.solidBlack), videoState: state)
        try store.save(draft, session: store.beginSession(for: draft.originalID))
        let bytes = try Data(contentsOf: store.url(for: draft.originalID))
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: bytes))
        let reopened = EditorDraftStore(directory: directory)
        let restored = try XCTUnwrap(reopened.load(id: draft.originalID)?.videoState)
        XCTAssertEqual(restored.manualRegions?.first?.rect, rect)
        XCTAssertEqual(restored.manualRegions?.first?.end, 2)
        XCTAssertEqual(restored.groups?.first?.trackIDs, [7, 8])
        XCTAssertEqual(restored.timeline?.frames.first?.trackIDs, [7])
    }
    func testIntervalsAreFiniteWithinDurationAndEndExclusive() throws {
        let rect = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        XCTAssertNil(VideoManualRegion(rect: rect, start: -1, end: 2, duration: 3))
        XCTAssertNil(VideoManualRegion(rect: rect, start: 1, end: 4, duration: 3))
        XCTAssertNil(VideoManualRegion(rect: rect, start: 1, end: 1, duration: 3))
        XCTAssertNil(VideoManualRegion(rect: rect, start: .nan, end: 2, duration: 3))
        let region = try XCTUnwrap(VideoManualRegion(rect: rect, start: 1, end: 2, duration: 3))
        XCTAssertFalse(region.contains(0.999))
        XCTAssertTrue(region.contains(1))
        XCTAssertFalse(region.contains(2))
    }
}
