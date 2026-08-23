import AVFoundation
import XCTest
@testable import zeroNetRedact

final class VideoAudioProcessorTests: XCTestCase {
    func testAnonymousVoicePresetsPreserveSpeechClarity() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoVoiceClarityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let videoOnly = directory.appendingPathComponent("video.mp4")
        let speech = directory.appendingPathComponent("speech-spectrum.m4a")
        let source = directory.appendingPathComponent("source-with-speech.mp4")
        try await VideoTestFixture.makeVideo(at: videoOnly, frameCount: 15)
        try VideoTestFixture.makeSpeechSpectrumM4A(at: speech)
        try await VideoMuxer().replaceAudio(videoURL: videoOnly, audioURL: speech, destinationURL: source)

        let sourceMetrics = try Self.metrics(of: speech)
        for preset in [VoicePreset.anonymousMale, .anonymousFemale, .robot] {
            let output = directory.appendingPathComponent("clarity-\(preset.rawValue).m4a")
            _ = try await VideoAudioProcessor().process(
                sourceVideoURL: source,
                destinationURL: output,
                preset: preset
            )
            let metrics = try Self.metrics(of: output)
            let centroidRatio = metrics.spectralCentroid / sourceMetrics.spectralCentroid

            XCTAssertTrue(
                0.8...1.25 ~= centroidRatio,
                "\(preset.rawValue) 语音频谱偏移过大: \(centroidRatio)"
            )
            XCTAssertTrue(
                0.6...1.6 ~= metrics.rms / sourceMetrics.rms,
                "\(preset.rawValue) 响度变化过大: \(metrics.rms / sourceMetrics.rms)"
            )
            XCTAssertLessThan(
                metrics.clippedSampleRatio,
                0.005,
                "\(preset.rawValue) 出现明显削波: \(metrics.clippedSampleRatio)"
            )
        }
    }

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

    private struct AudioMetrics {
        let rms: Double
        let spectralCentroid: Double
        let clippedSampleRatio: Double
    }

    private static func metrics(of url: URL) throws -> AudioMetrics {
        let file = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else { throw VideoProcessingError.exportFailed("Unable to allocate metrics buffer") }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            throw VideoProcessingError.exportFailed("Missing metrics channel")
        }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
        let clipped = samples.filter { abs($0) >= 0.98 }.count

        let windowSize = min(8_192, samples.count)
        let windowStart = max(0, samples.count / 2 - windowSize / 2)
        let window = Array(samples[windowStart..<(windowStart + windowSize)])
        let sampleRate = file.processingFormat.sampleRate
        var weightedPower = 0.0
        var totalPower = 0.0
        for frequency in stride(from: 100.0, through: 5_000.0, by: 20.0) {
            var real = 0.0
            var imaginary = 0.0
            for (index, sample) in window.enumerated() {
                let angle = 2 * Double.pi * frequency * Double(index) / sampleRate
                let hann = 0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(windowSize - 1))
                real += Double(sample) * hann * cos(angle)
                imaginary -= Double(sample) * hann * sin(angle)
            }
            let power = real * real + imaginary * imaginary
            totalPower += power
            weightedPower += frequency * power
        }
        return AudioMetrics(
            rms: rms,
            spectralCentroid: weightedPower / max(totalPower, .leastNonzeroMagnitude),
            clippedSampleRatio: Double(clipped) / Double(samples.count)
        )
    }
}
