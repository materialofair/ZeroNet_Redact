import AVFoundation
import Foundation
@testable import zeroNetRedact

enum VideoTestFixture {
    static func makeVideo(
        at url: URL,
        frameCount: Int = 10,
        frameRate: Int32 = 10,
        transform: CGAffineTransform = .identity
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 320,
                AVVideoHeightKey: 240,
            ]
        )
        input.transform = transform
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 240,
            ]
        )
        guard writer.canAdd(input) else {
            throw VideoProcessingError.exportFailed("Cannot add fixture video input")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? VideoProcessingError.exportFailed("Cannot start fixture writer")
        }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw VideoProcessingError.exportFailed("Missing fixture pixel buffer pool")
            }
            var optionalBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
            guard let buffer = optionalBuffer else {
                throw VideoProcessingError.exportFailed("Unable to allocate fixture frame")
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(frame * 18), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: frameRate)
            ) else {
                throw writer.error ?? VideoProcessingError.exportFailed("Fixture frame append failed")
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status != .completed {
            throw writer.error ?? VideoProcessingError.exportFailed("Fixture video creation failed")
        }
    }

    static func makeToneM4A(at url: URL, duration: Double = 1) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw VideoProcessingError.exportFailed("Unable to create fixture audio format")
        }
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let channel = buffer.floatChannelData?[0]
        else {
            throw VideoProcessingError.exportFailed("Unable to create fixture audio buffer")
        }
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            channel[index] = sin(Float(index) * 2 * .pi * 220 / Float(sampleRate)) * 0.2
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
            ]
        )
        try file.write(from: buffer)
    }

    /// 用覆盖元音与辅音关键频段的复合音近似语音频谱，避免单一低频音
    /// 无法暴露变声后发闷、发尖或过度失真的问题。
    static func makeSpeechSpectrumM4A(at url: URL, duration: Double = 1.5) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw VideoProcessingError.exportFailed("Unable to create speech fixture format")
        }
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let channel = buffer.floatChannelData?[0]
        else {
            throw VideoProcessingError.exportFailed("Unable to create speech fixture buffer")
        }
        let components: [(frequency: Double, amplitude: Double)] = [
            (180, 0.08), (700, 0.07), (1_400, 0.065), (2_800, 0.055), (3_800, 0.045),
        ]
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            let time = Double(index) / sampleRate
            let syllableEnvelope = 0.65 + 0.35 * sin(2 * .pi * 3.2 * time)
            channel[index] = Float(components.reduce(0.0) { value, component in
                value + sin(2 * .pi * component.frequency * time) * component.amplitude
            } * syllableEnvelope)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ]
        )
        try file.write(from: buffer)
    }
}
