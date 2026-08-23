@preconcurrency import AVFoundation
import Foundation

nonisolated final class VideoAudioProcessor: @unchecked Sendable {
    /// 处理默认音轨并输出 AAC/M4A。输入无音轨时返回 nil。
    func process(
        sourceVideoURL: URL,
        destinationURL: URL,
        preset: VoicePreset,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL? {
        guard preset != .original, preset != .mute else { return nil }
        let asset = AVURLAsset(url: sourceVideoURL)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { return nil }

        let extractedURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent("extracted-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: extractedURL) }
        try await extractAudio(from: asset, to: extractedURL)
        try Task.checkCancellation()
        progress(0.15)

        try await Task.detached(priority: .userInitiated) {
            try self.renderOffline(
                inputURL: extractedURL,
                outputURL: destinationURL,
                preset: preset,
                progress: { value in progress(0.15 + value * 0.85) }
            )
        }.value
        try Task.checkCancellation()
        // renderOffline 返回后 AVAudioFile 已释放、m4a header 已落盘，此时才能安全复读校验。
        try validateProcessedAudio(sourceURL: extractedURL, outputURL: destinationURL)
        return destinationURL
    }

    private func extractAudio(from asset: AVAsset, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { throw VideoProcessingError.unableToCreateExporter }
        try? FileManager.default.removeItem(at: url)
        session.outputURL = url
        session.outputFileType = .m4a
        session.metadata = []
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.exportAsynchronously {
                    if session.status == .completed {
                        continuation.resume()
                    } else if session.status == .cancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(
                            throwing: session.error
                                ?? VideoProcessingError.exportFailed(
                                    NSLocalizedString("voice.error.extract", comment: "")
                                )
                        )
                    }
                }
            }
        } onCancel: {
            session.cancelExport()
        }
    }

    /// 离线手动渲染。用 `AVAudioSourceNode` 的 render block 把解码后的 PCM 喂进
    /// engine（统一经 AVAudioConverter 归一化到 1–2 声道），而不是
    /// `AVAudioPlayerNode.scheduleFile` —— 后者在 iOS 的离线手动渲染模式下会输出静音
    /// （Apple 开发者论坛 thread 111249），多声道（>2ch）输入同样会触发静音
    /// （thread 119094）。source node 是手动渲染模式官方支持的输入方式。
    private func renderOffline(
        inputURL: URL,
        outputURL: URL,
        preset: VoicePreset,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let sourceFormat = inputFile.processingFormat
        let totalFrames = inputFile.length

        let channelCount = min(max(sourceFormat.channelCount, 1), 2)
        guard let renderFormat = AVAudioFormat(
            standardFormatWithSampleRate: sourceFormat.sampleRate,
            channels: channelCount
        ) else {
            throw VideoProcessingError.exportFailed(
                NSLocalizedString("voice.error.format", comment: "")
            )
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: renderFormat) else {
            throw VideoProcessingError.exportFailed(
                NSLocalizedString("voice.error.format", comment: "")
            )
        }
        let sourceNode = AVAudioSourceNode(format: renderFormat) {
            _,
            _,
            frameCount,
            outputData -> OSStatus in
            guard let fileBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: frameCount
            ) else { return noErr }
            do {
                try inputFile.read(into: fileBuffer, frameCount: frameCount)
            } catch {
                return noErr
            }
            guard fileBuffer.frameLength > 0 else { return noErr }
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: renderFormat,
                frameCapacity: fileBuffer.frameLength
            ) else { return noErr }
            var fed = false
            let status = converter.convert(to: outputBuffer, error: nil) { _, inputStatus in
                if fed {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                fed = true
                inputStatus.pointee = .haveData
                return fileBuffer
            }
            guard status == .haveData else { return noErr }
            let dest = UnsafeMutableAudioBufferListPointer(outputData)
            let src = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: outputBuffer.audioBufferList)
            )
            for index in 0..<min(dest.count, src.count) {
                dest[index].mNumberChannels = src[index].mNumberChannels
                dest[index].mDataByteSize = src[index].mDataByteSize
                dest[index].mData = src[index].mData
            }
            return noErr
        }

        let engine = AVAudioEngine()
        let pitch = AVAudioUnitTimePitch()
        let equalizer = AVAudioUnitEQ(numberOfBands: 2)
        let distortion = AVAudioUnitDistortion()

        configure(preset: preset, pitch: pitch, equalizer: equalizer, distortion: distortion)
        engine.attach(sourceNode)
        engine.attach(pitch)
        engine.attach(equalizer)
        engine.attach(distortion)
        engine.connect(sourceNode, to: pitch, format: renderFormat)
        engine.connect(pitch, to: equalizer, format: renderFormat)
        engine.connect(equalizer, to: distortion, format: renderFormat)
        engine.connect(distortion, to: engine.mainMixerNode, format: renderFormat)

        try engine.enableManualRenderingMode(
            .offline,
            format: renderFormat,
            maximumFrameCount: 4096
        )
        // 离线手动渲染也需要 start()，否则 renderOffline 返回 NotRunning(-80802)。
        try engine.start()

        try? FileManager.default.removeItem(at: outputURL)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: renderFormat.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: 128_000,
        ]
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw VideoProcessingError.exportFailed(
                NSLocalizedString("voice.error.buffer", comment: "")
            )
        }

        defer {
            engine.stop()
            engine.disableManualRenderingMode()
        }

        renderingLoop: while engine.manualRenderingSampleTime < totalFrames {
            if Task.isCancelled { throw CancellationError() }
            let remaining = totalFrames - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(
                min(AVAudioFramePosition(engine.manualRenderingMaximumFrameCount), remaining)
            )
            let status = try engine.renderOffline(frames, to: buffer)
            switch status {
            case .success:
                try outputFile.write(from: buffer)
            case .cannotDoInCurrentContext:
                continue
            case .insufficientDataFromInputNode:
                break renderingLoop
            case .error:
                throw VideoProcessingError.exportFailed(
                    NSLocalizedString("voice.error.render", comment: "")
                )
            @unknown default:
                throw VideoProcessingError.exportFailed(
                    NSLocalizedString("voice.error.render", comment: "")
                )
            }
            progress(min(1, Double(engine.manualRenderingSampleTime) / Double(totalFrames)))
        }
    }

    /// 校验变声结果：时长不能明显短于源音轨，且源音轨有声时输出不能是纯静音。
    /// iOS 上 `AVAudioPlayerNode` 离线渲染静音 bug 会产出全零数据，这里兜底拦截，
    /// 避免把无声视频静默导出。
    private func validateProcessedAudio(sourceURL: URL, outputURL: URL) throws {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let outputFile = try AVAudioFile(forReading: outputURL)
        let expectedFrames = sourceFile.length
        let outputFrames = outputFile.length
        let frameTolerance = max(AVAudioFramePosition(expectedFrames) / 5, 4_096)
        guard outputFrames > 0, abs(outputFrames - expectedFrames) <= frameTolerance else {
            throw VideoProcessingError.exportFailed(
                NSLocalizedString("voice.error.silent", comment: "")
            )
        }
        let sourcePeak = Self.peakMagnitude(of: sourceFile)
        let outputPeak = Self.peakMagnitude(of: outputFile)
        // 源音轨并非数字静音时，输出峰值几乎为 0 说明处理链没有产出声音。
        guard sourcePeak <= 0.01 || outputPeak >= 1e-5 else {
            throw VideoProcessingError.exportFailed(
                NSLocalizedString("voice.error.silent", comment: "")
            )
        }
    }

    private static func peakMagnitude(of file: AVAudioFile) -> Float {
        var peak: Float = 0
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: 4_096
        ) else { return peak }
        while true {
            do {
                try file.read(into: buffer, frameCount: 4_096)
            } catch {
                break
            }
            guard buffer.frameLength > 0 else { break }
            if let channels = buffer.floatChannelData {
                let frameLength = Int(buffer.frameLength)
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

    private func configure(
        preset: VoicePreset,
        pitch: AVAudioUnitTimePitch,
        equalizer: AVAudioUnitEQ,
        distortion: AVAudioUnitDistortion
    ) {
        pitch.rate = 1
        distortion.wetDryMix = 0

        let lowBand = equalizer.bands[0]
        lowBand.filterType = .lowShelf
        lowBand.frequency = 180
        lowBand.bypass = false
        let highBand = equalizer.bands[1]
        highBand.filterType = .highShelf
        highBand.frequency = 3_200
        highBand.bypass = false

        switch preset {
        case .anonymousMale:
            pitch.pitch = -500
            lowBand.gain = 0
            highBand.gain = 0
        case .anonymousFemale:
            pitch.pitch = 500
            lowBand.gain = 0
            highBand.gain = 0
        case .robot:
            pitch.pitch = 80
            lowBand.gain = 0
            highBand.gain = 2
            distortion.loadFactoryPreset(.speechRadioTower)
            distortion.wetDryMix = 48
        case .original, .mute:
            break
        }
    }
}
