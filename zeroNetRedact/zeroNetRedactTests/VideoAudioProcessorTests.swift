import AVFoundation
import XCTest
@testable import zeroNetRedact

final class VideoAudioProcessorTests: XCTestCase {
    func testFixedVoicePresetsProduceReadableAudioAndMuteRemovesTrack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoAudioProcessorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let videoOnly = directory.appendingPathComponent("video.mp4")
        let tone = directory.appendingPathComponent("tone.m4a")
        let source = directory.appendingPathComponent("source-with-audio.mp4")
        try await VideoTestFixture.makeVideo(at: videoOnly)
        try VideoTestFixture.makeToneM4A(at: tone)
        try await VideoMuxer().replaceAudio(videoURL: videoOnly, audioURL: tone, destinationURL: source)

        var renderedOutputs: [Data] = []
        for preset in [VoicePreset.anonymousMale, .anonymousFemale, .robot] {
            let audio = directory.appendingPathComponent("\(preset.rawValue).m4a")
            let result = try await VideoAudioProcessor().process(
                sourceVideoURL: source,
                destinationURL: audio,
                preset: preset
            )
            XCTAssertNotNil(result)
            let asset = AVURLAsset(url: audio)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            XCTAssertEqual(audioTracks.count, 1)
            XCTAssertEqual(
                duration,
                1,
                accuracy: 0.08
            )
            // 回归防护：iOS 上 AVAudioPlayerNode 离线渲染会输出静音，这里必须
            // 断言变声结果确实有声，而不是只有一个"时长正确"的空壳。
            let peak = try Self.peakMagnitude(of: audio)
            XCTAssertGreaterThan(peak, 0.005, "\(preset.rawValue) 输出峰值过低: \(peak)")
            renderedOutputs.append(try Data(contentsOf: audio))
        }
        XCTAssertEqual(Set(renderedOutputs).count, 3)

        let muted = directory.appendingPathComponent("muted.mp4")
        try await VideoMuxer().replaceAudio(videoURL: source, audioURL: nil, destinationURL: muted)
        let mutedAsset = AVURLAsset(url: muted)
        let mutedVideoTracks = try await mutedAsset.loadTracks(withMediaType: .video)
        let mutedAudioTracks = try await mutedAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(mutedVideoTracks.count, 1)
        XCTAssertTrue(mutedAudioTracks.isEmpty)
    }

    private static func peakMagnitude(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        var peak: Float = 0
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: 4_096
        ) else { return peak }
        while true {
            try? file.read(into: buffer, frameCount: 4_096)
            guard buffer.frameLength > 0 else { break }
            let frameLength = Int(buffer.frameLength)
            if let channels = buffer.floatChannelData {
                let channelCount = Int(buffer.format.channelCount)
                for channel in 0..<channelCount {
                    let samples = channels[channel]
                    for index in 0..<frameLength {
                        peak = max(peak, abs(samples[index]))
                    }
                }
            }
        }
        return peak
    }
}
