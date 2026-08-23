import XCTest

@testable import zeroNetRedact

@MainActor
final class ImageFaceReviewStateTests: XCTestCase {
    func testCandidatesStartSelectedAndCanExcludeMany() {
        let candidates = [
            ImageFaceCandidate(rect: CGRect(x: 0, y: 0, width: 10, height: 10)),
            ImageFaceCandidate(rect: CGRect(x: 20, y: 0, width: 10, height: 10)),
        ]
        var state = ImageFaceReviewState(candidates: candidates)
        XCTAssertEqual(state.selectedIDs.count, 2)
        state.toggle(candidates[0].id)
        state.toggle(candidates[1].id)
        XCTAssertTrue(state.selectedIDs.isEmpty)
        state.toggle(candidates[0].id)
        XCTAssertEqual(state.selectedIDs, [candidates[0].id])
        state.selectAll()
        XCTAssertEqual(state.selectedIDs.count, 2)
        state.deselectAll()
        XCTAssertTrue(state.selectedIDs.isEmpty)
    }

    func testExistingStickerAtSeventyPercentIoUIsExcluded() {
        let duplicate = ImageFaceCandidate(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let newFace = ImageFaceCandidate(rect: CGRect(x: 30, y: 0, width: 10, height: 10))
        let filtered = ImageFaceReviewState.excludingAlreadyProtected(
            [duplicate, newFace],
            existingRects: [CGRect(x: 0, y: 0, width: 10, height: 10)]
        )
        XCTAssertEqual(filtered, [newFace])
    }

    func testStickerPurchaseAndExportPurchaseResolveSeparately() {
        var selection = FaceStickerSelectionState()
        var intent = ImageEditorPremiumIntentState()
        XCTAssertFalse(selection.request(.panda, hasUnlimitedAccess: false))
        intent.present(.faceSticker(.panda))
        XCTAssertEqual(
            intent.resolveDismissal(hasUnlimitedAccess: true, selection: &selection),
            .applySticker(.panda)
        )

        intent.present(.export)
        XCTAssertEqual(
            intent.resolveDismissal(hasUnlimitedAccess: true, selection: &selection),
            .retryExport
        )
    }

    func testCancelledPurchaseKeepsCurrentSticker() {
        var selection = FaceStickerSelectionState()
        var intent = ImageEditorPremiumIntentState()
        XCTAssertFalse(selection.request(.lion, hasUnlimitedAccess: false))
        intent.present(.faceSticker(.lion))
        XCTAssertEqual(
            intent.resolveDismissal(hasUnlimitedAccess: false, selection: &selection),
            .none
        )
        XCTAssertEqual(selection.selected, .orangeSmiley)
    }

    func testImageAndVideoPremiumIntentsKeepEquivalentOutcomes() {
        for sticker in FaceRedactionSticker.allCases where sticker.requiresPremium {
            var imageSelection = FaceStickerSelectionState()
            var imageIntent = ImageEditorPremiumIntentState()
            XCTAssertFalse(imageSelection.request(sticker, hasUnlimitedAccess: false))
            imageIntent.present(.faceSticker(sticker))

            var videoSelection = VideoStickerSelectionState()
            var videoIntent = VideoPremiumIntentState()
            XCTAssertFalse(videoSelection.request(sticker, hasUnlimitedAccess: false))
            videoIntent.present(.sticker(sticker))

            let imageAction = imageIntent.resolveDismissal(
                hasUnlimitedAccess: true,
                selection: &imageSelection
            )
            let videoAction = videoIntent.resolveDismissal(
                hasUnlimitedAccess: true,
                selection: &videoSelection
            )

            XCTAssertEqual(imageSelection.selected, videoSelection.selected)
            XCTAssertEqual(imageAction, .applySticker(sticker))
            XCTAssertEqual(videoAction, .applySticker(sticker))
        }
    }
}
