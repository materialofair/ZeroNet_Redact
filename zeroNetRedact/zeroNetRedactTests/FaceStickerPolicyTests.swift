import CoreImage
import XCTest

@testable import zeroNetRedact

final class FaceStickerPolicyTests: XCTestCase {
    func testSharedCatalogKeepsVideoPricing() {
        XCTAssertEqual(FaceRedactionSticker.allCases.count, 9)
        XCTAssertEqual(
            FaceRedactionSticker.allCases.filter { !$0.requiresPremium },
            [.orangeSmiley, .blueSmiley]
        )
    }

    func testLockedSharedSelectionIsPendingOnly() {
        var state = FaceStickerSelectionState()
        XCTAssertTrue(state.request(.blueSmiley, hasUnlimitedAccess: false))
        XCTAssertFalse(state.request(.panda, hasUnlimitedAccess: false))
        XCTAssertEqual(state.selected, .blueSmiley)
        XCTAssertEqual(state.pendingPremiumSticker, .panda)
    }

    func testEverySharedStickerIsOpaqueAtPrivacySamplePoints() throws {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        for sticker in FaceRedactionSticker.allCases {
            let image = FaceStickerRenderer.image(
                for: sticker,
                size: CGSize(width: 64, height: 64)
            )
            let ciImage = try XCTUnwrap(CIImage(image: image))
            var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
            context.render(
                ciImage,
                toBitmap: &bytes,
                rowBytes: 64 * 4,
                bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
            for point in [
                CGPoint(x: 0, y: 0), CGPoint(x: 63, y: 0),
                CGPoint(x: 0, y: 63), CGPoint(x: 63, y: 63),
                CGPoint(x: 32, y: 32),
            ] {
                let offset = (Int(point.y) * 64 + Int(point.x)) * 4
                XCTAssertEqual(bytes[offset + 3], 255, "\(sticker) leaked alpha")
            }
        }
    }
}
