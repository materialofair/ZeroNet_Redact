import AVFoundation
import CoreGraphics
import XCTest
@testable import zeroNetRedact

final class FaceTrackSmootherTests: XCTestCase {
    func testPrivacyExpansionClampsToFrame() {
        let expanded = CGRect(x: 0, y: 0, width: 0.2, height: 0.3)
            .expandedForPrivacy(scale: 1.3)

        XCTAssertEqual(expanded.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(expanded.minY, 0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(expanded.maxX, 1)
        XCTAssertLessThanOrEqual(expanded.maxY, 1)
    }

    func testShortMissRetainsAndExpandsCover() {
        var smoother = FaceTrackSmoother(maximumMissedFrames: 2, smoothing: 0.5)
        let original = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        _ = smoother.update(with: [original])

        let firstMiss = smoother.update(with: [])
        XCTAssertEqual(firstMiss.count, 1)
        XCTAssertGreaterThan(firstMiss[0].width, original.width)

        XCTAssertEqual(smoother.update(with: []).count, 1)
        XCTAssertTrue(smoother.update(with: []).isEmpty)
    }

    func testTwoFacesRemainTwoTracksWhenDetectionOrderChanges() {
        var smoother = FaceTrackSmoother()
        let left = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.2)
        let right = CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.2)
        _ = smoother.update(with: [left, right])

        let result = smoother.update(with: [right.offsetBy(dx: -0.01, dy: 0), left.offsetBy(dx: 0.01, dy: 0)])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(smoother.createdTrackCount, 2)
    }

    func testTimelineUsesNearestFrame() {
        let first = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let second = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        let timeline = VideoFaceTimeline(
            frames: [
                VideoFaceFrame(seconds: 0, normalizedRects: [first]),
                VideoFaceFrame(seconds: 1, normalizedRects: [second]),
            ],
            frameRate: 1,
            totalUniqueFaces: 1
        )

        XCTAssertEqual(timeline.rects(at: CMTime(seconds: 0.2, preferredTimescale: 600)), [first])
        XCTAssertEqual(timeline.rects(at: CMTime(seconds: 0.8, preferredTimescale: 600)), [second])
    }
}
