import AVFoundation
import XCTest
@testable import zeroNetRedact

final class VideoExporterTests: XCTestCase {
    func testExportProducesReadableH264VideoWithMatchingDuration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await VideoTestFixture.makeVideo(at: source)
        let timeline = VideoFaceTimeline(
            frames: (0..<10).map {
                VideoFaceFrame(
                    seconds: Double($0) / 10,
                    normalizedRects: [CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)]
                )
            },
            frameRate: 10,
            totalUniqueFaces: 1
        )

        try await VideoExporter().export(
            sourceURL: source,
            destinationURL: output,
            timeline: timeline,
            effect: .cartoonSticker
        )

        let sourceAsset = AVURLAsset(url: source)
        let outputAsset = AVURLAsset(url: output)
        let sourceDuration = CMTimeGetSeconds(try await sourceAsset.load(.duration))
        let outputDuration = CMTimeGetSeconds(try await outputAsset.load(.duration))
        let tracks = try await outputAsset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(outputDuration, sourceDuration, accuracy: 0.11)
        let formats = try await tracks[0].load(.formatDescriptions)
        XCTAssertTrue(
            formats.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }
        )
    }

    func testOriginalAudioTrackIsPreserved() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoExporterAudioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let videoOnly = directory.appendingPathComponent("video.mp4")
        let tone = directory.appendingPathComponent("tone.m4a")
        let source = directory.appendingPathComponent("source.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await VideoTestFixture.makeVideo(at: videoOnly)
        try VideoTestFixture.makeToneM4A(at: tone)
        try await VideoMuxer().replaceAudio(videoURL: videoOnly, audioURL: tone, destinationURL: source)

        try await VideoExporter().export(
            sourceURL: source,
            destinationURL: output,
            timeline: VideoFaceTimeline(
                frames: [VideoFaceFrame(seconds: 0, normalizedRects: [])],
                frameRate: 10,
                totalUniqueFaces: 0
            ),
            effect: .strongBlur
        )

        let outputAsset = AVURLAsset(url: output)
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
    }

    func testPortraitTransformProducesPortraitDisplayDimensions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoExporterRotationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("rotated.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        let portraitTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 240, ty: 0)
        try await VideoTestFixture.makeVideo(at: source, transform: portraitTransform)

        try await VideoExporter().export(
            sourceURL: source,
            destinationURL: output,
            timeline: VideoFaceTimeline(
                frames: [VideoFaceFrame(seconds: 0, normalizedRects: [])],
                frameRate: 10,
                totalUniqueFaces: 0
            ),
            effect: .strongBlur
        )

        let outputAsset = AVURLAsset(url: output)
        let tracks = try await outputAsset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displayed = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        XCTAssertLessThan(displayed.width, displayed.height)
        XCTAssertEqual(displayed.width, 240, accuracy: 1)
        XCTAssertEqual(displayed.height, 320, accuracy: 1)
    }

}
