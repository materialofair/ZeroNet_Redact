import AVFoundation
import XCTest
@testable import zeroNetRedact

final class VideoExporterTests: XCTestCase {
    private func emptyTimeline() -> VideoFaceTimeline {
        VideoFaceTimeline(
            frames: [VideoFaceFrame(seconds: 0, normalizedRects: [])],
            frameRate: 10,
            totalUniqueFaces: 0
        )
    }

    private func timeline(rects: [CGRect] = []) -> VideoFaceTimeline {
        VideoFaceTimeline(
            frames: (0..<10).map {
                VideoFaceFrame(
                    seconds: Double($0) / 10,
                    normalizedRects: rects.isEmpty
                        ? [CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)]
                        : rects
                )
            },
            frameRate: 10,
            totalUniqueFaces: 1
        )
    }

    func testExportProducesReadableH264OrHEVCVideoWithMatchingDuration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await VideoTestFixture.makeVideo(at: source)

        try await VideoExporter().export(
            sourceURL: source,
            destinationURL: output,
            timeline: timeline(),
            sticker: .orangeSmiley
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
            formats.contains {
                let subtype = CMFormatDescriptionGetMediaSubType($0)
                return subtype == kCMVideoCodecType_H264 || subtype == kCMVideoCodecType_HEVC
            }
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
            timeline: emptyTimeline(),
            sticker: .orangeSmiley
        )

        let outputAsset = AVURLAsset(url: output)
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
    }

    func testExportWithMuteDropsAudioTrack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoExporterMuteTests-\(UUID().uuidString)", isDirectory: true)
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
            timeline: emptyTimeline(),
            sticker: .orangeSmiley,
            audio: .mute
        )

        let outputAsset = AVURLAsset(url: output)
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audioTracks.isEmpty)
    }

    func testExportWithReplacedAudioInsertsProvidedTrack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoExporterReplaceAudioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let videoOnly = directory.appendingPathComponent("video.mp4")
        let tone = directory.appendingPathComponent("tone.m4a")
        let output = directory.appendingPathComponent("output.mp4")
        try await VideoTestFixture.makeVideo(at: videoOnly)
        try VideoTestFixture.makeToneM4A(at: tone)

        try await VideoExporter().export(
            sourceURL: videoOnly,
            destinationURL: output,
            timeline: emptyTimeline(),
            sticker: .orangeSmiley,
            audio: .replace(tone)
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
            timeline: emptyTimeline(),
            sticker: .orangeSmiley
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

// MARK: - Redaction coverage & frame-rate regression checks

final class VideoExporterRedactionTests: XCTestCase {
    /// 生成 30fps 灰底 + 中心绿色方块的测试视频（960x540）。
    private func makeSquareVideo(at url: URL, frameRate: Int32 = 30, frameCount: Int = 60) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 960,
            AVVideoHeightKey: 540,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 960,
            kCVPixelBufferHeightKey as String: 540,
        ])
        guard writer.canAdd(input) else {
            throw VideoProcessingError.exportFailed("cannot add fixture input")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? VideoProcessingError.exportFailed("cannot start fixture writer")
        }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw VideoProcessingError.exportFailed("missing fixture pool")
            }
            var optionalBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
            guard let buffer = optionalBuffer else {
                throw VideoProcessingError.exportFailed("unable to allocate fixture frame")
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let ctx = CGContext(
                    data: base,
                    width: 960,
                    height: 540,
                    bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue
                )
                let gray = 30 + (frame % 3) * 20
                ctx?.setFillColor(CGColor(red: CGFloat(gray) / 255, green: CGFloat(gray) / 255, blue: CGFloat(gray) / 255, alpha: 1))
                ctx?.fill(CGRect(x: 0, y: 0, width: 960, height: 540))
                ctx?.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
                ctx?.fill(CGRect(x: 360, y: 190, width: 240, height: 160))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: frameRate)) else {
                throw writer.error ?? VideoProcessingError.exportFailed("fixture frame append failed")
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status != .completed {
            throw writer.error ?? VideoProcessingError.exportFailed("fixture video creation failed")
        }
    }

    private func pixel(of url: URL, at seconds: Double, x: Int, y: Int) async throws -> [UInt8] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var actualTime = CMTime.zero
        let image = try generator.copyCGImage(
            at: CMTime(seconds: seconds, preferredTimescale: 600),
            actualTime: &actualTime
        )
        let ci = CIImage(cgImage: image)
        let context = CIContext()
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            ci,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes
    }

    /// 回归：导出必须真的把时间轴上的脱敏画上去（不能因为 HEVC/合成改动变成空操作）。
    func testExportActuallyAppliesRedactionAndKeepsSourceFrameRate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoExporterCoverageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await makeSquareVideo(at: source, frameRate: 30, frameCount: 60)

        // 绿色方块归一化区域：(360,190,240,160) / (960,540)；注意用浮点除法，避免整型截断为零。
        let square = CGRect(x: 360.0 / 960.0, y: 190.0 / 540.0, width: 240.0 / 960.0, height: 160.0 / 540.0)
        let timeline = VideoFaceTimeline(
            frames: (0..<20).map { index in
                VideoFaceFrame(
                    seconds: Double(index) / 10,
                    normalizedRects: [square]
                )
            },
            // 模拟当前分析器的输出：采样 10fps、frameRate 上报 10。
            frameRate: 10,
            totalUniqueFaces: 1
        )

        try await VideoExporter().export(
            sourceURL: source,
            destinationURL: output,
            timeline: timeline,
            sticker: .orangeSmiley,
            audio: .original
        )

        // 1) 方块中心（480,270）应被贴纸覆盖：橙色调（R 高、B 低）而非绿色（G 高）。
        let center = try await pixel(of: output, at: 0.1, x: 480, y: 270)
        XCTAssertEqual(center[3], 255, "中心应不透明")
        XCTAssertGreaterThan(center[0], center[2], "应为橙色贴纸（R>B），实际 \(center)")
        XCTAssertLessThan(center[1], 200, "绿色应被覆盖（G 不应接近 255），实际 \(center)")

        // 2) 角落（远离贴纸）仍是灰底（R≈G≈B）。
        let corner = try await pixel(of: output, at: 0.1, x: 40, y: 40)
        XCTAssertEqual(corner[0], corner[1], accuracy: 8, "角落应为灰色，实际 \(corner)")

        // 3) 输出帧率应保持源帧率（30fps），不能因为 10fps 采样变成 10fps。
        let track = try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first!
        let outputRate = try await track.load(.nominalFrameRate)
        XCTAssertEqual(Double(outputRate), 30, accuracy: 1.5, "导出帧率应保持 30fps，实际 \(outputRate)")
    }
}
