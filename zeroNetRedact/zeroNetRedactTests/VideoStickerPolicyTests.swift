import UIKit
import XCTest
@testable import zeroNetRedact

final class VideoStickerPolicyTests: XCTestCase {
    func testOnlyOrangeAndBlueSmileysAreFree() {
        let free = VideoRedactionSticker.allCases.filter { !$0.requiresPremium }
        XCTAssertEqual(free, [.orangeSmiley, .blueSmiley])

        let premium = VideoRedactionSticker.allCases.filter(\.requiresPremium)
        XCTAssertEqual(premium.count, 7)
        XCTAssertTrue(premium.allSatisfy { $0.isLocked(hasUnlimitedAccess: false) })
        XCTAssertTrue(premium.allSatisfy { !$0.isLocked(hasUnlimitedAccess: true) })
    }

    func testEveryPremiumStickerLoadsBundledVectorArtwork() {
        for sticker in VideoRedactionSticker.allCases where sticker.requiresPremium {
            guard case .asset(let assetName) = sticker.artwork else {
                return XCTFail("\(sticker.rawValue) 应使用打包的开源素材")
            }
            XCTAssertNotNil(UIImage(named: assetName), "缺少素材：\(assetName)")
        }
    }

    func testLockedSelectionDoesNotReplaceCurrentStickerUntilPremiumResolves() {
        var state = VideoStickerSelectionState()

        XCTAssertTrue(state.request(.blueSmiley, hasUnlimitedAccess: false))
        XCTAssertEqual(state.selected, .blueSmiley)

        XCTAssertFalse(state.request(.panda, hasUnlimitedAccess: false))
        XCTAssertEqual(state.selected, .blueSmiley)
        XCTAssertEqual(state.pendingPremiumSticker, .panda)

        XCTAssertNil(state.resolvePremiumRequest(hasUnlimitedAccess: false))
        XCTAssertEqual(state.selected, .blueSmiley)
        XCTAssertNil(state.pendingPremiumSticker)
    }

    func testLatestLockedRequestWinsAndPurchaseAppliesIt() {
        var state = VideoStickerSelectionState()

        XCTAssertFalse(state.request(.panda, hasUnlimitedAccess: false))
        XCTAssertFalse(state.request(.robot, hasUnlimitedAccess: false))
        XCTAssertEqual(state.pendingPremiumSticker, .robot)
        XCTAssertEqual(state.resolvePremiumRequest(hasUnlimitedAccess: true), .robot)
        XCTAssertEqual(state.selected, .robot)
    }

    func testPresentationPolicyDistinguishesArtworkLockAndAccessibility() {
        XCTAssertEqual(
            VideoRedactionSticker.orangeSmiley.artwork,
            .systemImage("face.smiling.inverse")
        )
        XCTAssertEqual(VideoRedactionSticker.heartEyes.artwork, .asset("StickerHeartEyes"))
        XCTAssertNotEqual(
            VideoRedactionSticker.heartEyes.accessibilityValue(hasUnlimitedAccess: false),
            VideoRedactionSticker.heartEyes.accessibilityValue(hasUnlimitedAccess: true)
        )
    }

    func testPremiumIntentIsExplicitLatestWinsAndConsumedOnce() {
        var state = VideoPremiumIntentState()

        state.present(.export)
        state.present(.sticker(.lion))
        XCTAssertEqual(state.consume(), .sticker(.lion))
        XCTAssertNil(state.consume())
    }

    func testStickerDismissalAppliesStickerWithoutRetryingExport() {
        var selection = VideoStickerSelectionState()
        var intent = VideoPremiumIntentState()

        XCTAssertFalse(selection.request(.robot, hasUnlimitedAccess: false))
        intent.present(.sticker(.robot))

        XCTAssertEqual(
            intent.resolveDismissal(hasUnlimitedAccess: true, selection: &selection),
            .applySticker(.robot)
        )
        XCTAssertEqual(selection.selected, .robot)
        XCTAssertNil(intent.current)
    }

    func testExportDismissalRetriesExportWithoutApplyingPendingSticker() {
        var selection = VideoStickerSelectionState()
        var intent = VideoPremiumIntentState()

        XCTAssertFalse(selection.request(.panda, hasUnlimitedAccess: false))
        intent.present(.export)

        XCTAssertEqual(
            intent.resolveDismissal(hasUnlimitedAccess: true, selection: &selection),
            .retryExport
        )
        XCTAssertEqual(selection.selected, .orangeSmiley)
        XCTAssertNil(selection.pendingPremiumSticker)
    }

    func testCancelledPurchaseProducesNoDismissalAction() {
        var selection = VideoStickerSelectionState()
        var intent = VideoPremiumIntentState()

        XCTAssertFalse(selection.request(.lion, hasUnlimitedAccess: false))
        intent.present(.sticker(.lion))

        XCTAssertEqual(
            intent.resolveDismissal(hasUnlimitedAccess: false, selection: &selection),
            .none
        )
        XCTAssertEqual(selection.selected, .orangeSmiley)
        XCTAssertNil(selection.pendingPremiumSticker)
    }
}
