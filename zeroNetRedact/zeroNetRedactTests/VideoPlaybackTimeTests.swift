import AVFoundation
import XCTest
@testable import zeroNetRedact

@MainActor
final class VideoPlaybackTimeTests: XCTestCase {
    func testPlayerWithoutCurrentItemHasNoResumeTime() {
        let player = AVPlayer()

        XCTAssertNil(VideoPlaybackTime.resumeTime(from: player))
    }

    func testNumericCurrentTimeCanBeResumed() {
        let time = CMTime(seconds: 1.25, preferredTimescale: 600)

        XCTAssertEqual(VideoPlaybackTime.validated(time), time)
    }

    func testInvalidIndefiniteAndNegativeTimesCannotBeResumed() {
        XCTAssertNil(VideoPlaybackTime.validated(.invalid))
        XCTAssertNil(VideoPlaybackTime.validated(.indefinite))
        XCTAssertNil(VideoPlaybackTime.validated(CMTime(seconds: -1, preferredTimescale: 600)))
    }
}
