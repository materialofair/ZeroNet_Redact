@preconcurrency import AVFoundation
import Foundation

nonisolated final class VideoMuxer: @unchecked Sendable {
    /// 用源视频轨（含旋转变换）和可选音轨构建导出 composition。
    /// 供换音/静音导出与测试复用，保证音画同步与方向一致。
    static func makeComposition(videoURL: URL, audioURL: URL?) async throws -> AVAsset {
        let videoAsset = AVURLAsset(url: videoURL)
        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessingError.missingVideoTrack
        }
        let duration = try await videoAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw VideoProcessingError.unableToCreateComposition }
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        if let audioURL {
            let audioAsset = AVURLAsset(url: audioURL)
            if let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
                let audioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            {
                let audioDuration = min(duration, try await audioAsset.load(.duration))
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: audioDuration),
                    of: sourceAudio,
                    at: .zero
                )
            }
        }
        return composition
    }

    func replaceAudio(
        videoURL: URL,
        audioURL: URL?,
        destinationURL: URL
    ) async throws {
        let composition = try await Self.makeComposition(videoURL: videoURL, audioURL: audioURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw VideoProcessingError.unableToCreateExporter }
        try? FileManager.default.removeItem(at: destinationURL)
        session.outputURL = destinationURL
        session.outputFileType = .mp4
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
                                    NSLocalizedString("video.error.exportFailed", comment: "")
                                )
                        )
                    }
                }
            }
        } onCancel: {
            session.cancelExport()
        }

        let outputAsset = AVURLAsset(url: destinationURL)
        guard let outputVideo = try await outputAsset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessingError.missingVideoTrack
        }
        let formats = try await outputVideo.load(.formatDescriptions)
        guard formats.contains(where: {
            CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264
        }) else {
            throw VideoProcessingError.unexpectedVideoCodec
        }

        // 需要换音时，导出产物必须真的带音频轨；否则说明音轨在处理中丢失
        // （例如变声输出为空），不允许静默导出无声视频。
        if audioURL != nil {
            let outputAudio = try await outputAsset.loadTracks(withMediaType: .audio)
            guard !outputAudio.isEmpty else {
                throw VideoProcessingError.missingAudioTrack
            }
        }
    }
}
