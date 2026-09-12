import AVFoundation
import XCTest
@testable import zeroNetRedact

final class VideoFaceAnalyzerTests: XCTestCase {
    func testSequentialAnalysisReadsEntireVideo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("analysis-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await VideoTestFixture.makeVideo(at: url)
        let timeline = try await VideoFaceAnalyzer().analyze(url: url)
        XCTAssertEqual(timeline.frameRate, 10)
        XCTAssertEqual(timeline.frames.count, 10)
        XCTAssertEqual(try XCTUnwrap(timeline.frames.first).seconds, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(timeline.frames.last).seconds, 0.9, accuracy: 0.001)
        XCTAssertTrue(timeline.frames.allSatisfy { $0.normalizedRects.isEmpty })
    }

    func testPortraitAnalysisUsesDisplayOrientation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-analysis-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await VideoTestFixture.makeVideo(
            at: url, transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 240, ty: 0)
        )
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let composition = try await VideoFaceAnalyzer.analysisComposition(
            track: track, duration: try await asset.load(.duration), frameRate: 10
        )
        XCTAssertEqual(composition.renderSize, CGSize(width: 240, height: 320))
        let timeline = try await VideoFaceAnalyzer().analyze(url: url)
        XCTAssertEqual(timeline.frames.count, 10)
    }

    func testHighFrameRateSourceUsesExistingThirtyFPSSampling() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rate-analysis-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await VideoTestFixture.makeVideo(at: url, frameCount: 60, frameRate: 60)
        let timeline = try await VideoFaceAnalyzer().analyze(url: url)
        XCTAssertEqual(timeline.frameRate, 30)
        XCTAssertEqual(timeline.frames.count, 30)
        XCTAssertEqual(try XCTUnwrap(timeline.frames.last).seconds, 29.0 / 30, accuracy: 0.001)
    }

    func testCancellationReachesAnalysisWorker() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VideoFaceAnalyzer().analyze(url: URL(fileURLWithPath: "/missing.mp4"))
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled analysis must not succeed")
        } catch is CancellationError {
        }
    }
}
