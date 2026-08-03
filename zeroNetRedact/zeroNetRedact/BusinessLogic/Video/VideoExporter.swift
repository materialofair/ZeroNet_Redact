import AVFoundation
import Foundation

/// 导出时如何处理音轨：
/// - `original`：保留源视频音轨（直接导出，音轨原样转封装）。
/// - `mute`：去掉音轨（导出阶段直接不加入音轨，避免二次转码）。
/// - `replace(URL)`：用已处理好的音频文件替换源音轨。
enum VideoExportAudio: Sendable {
    case original
    case mute
    case replace(URL)
}

final class VideoExporter {
    func export(
        sourceURL: URL,
        destinationURL: URL,
        timeline: VideoFaceTimeline,
        sticker: VideoRedactionSticker,
        audio: VideoExportAudio = .original,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw VideoProcessingError.missingVideoTrack
        }

        // 原声直接导出；静音/换音通过 composition 一次完成，视频只编码一遍。
        let exportAsset: AVAsset
        switch audio {
        case .original:
            exportAsset = asset
        case .mute:
            exportAsset = try await VideoMuxer.makeComposition(videoURL: sourceURL, audioURL: nil)
        case .replace(let audioURL):
            exportAsset = try await VideoMuxer.makeComposition(videoURL: sourceURL, audioURL: audioURL)
        }

        guard let session = AVAssetExportSession(
            asset: exportAsset,
            presetName: Self.preferredPreset(for: exportAsset)
        ) else {
            throw VideoProcessingError.unableToCreateExporter
        }

        try? FileManager.default.removeItem(at: destinationURL)
        session.outputURL = destinationURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = false
        session.metadata = []
        session.videoComposition = VideoCompositionFactory.make(
            asset: exportAsset,
            timeline: timeline,
            sticker: sticker
        )

        let monitor = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { monitor.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.exportAsynchronously {
                    switch session.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(
                            throwing: VideoProcessingError.exportFailed(
                                session.error?.localizedDescription
                                    ?? NSLocalizedString("video.error.exportFailed", comment: "")
                            )
                        )
                    }
                }
            }
        } onCancel: {
            session.cancelExport()
        }

        let outputAsset = AVURLAsset(url: destinationURL)
        guard let track = try await outputAsset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessingError.missingVideoTrack
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard descriptions.contains(where: { Self.isSupportedVideoCodec($0) }) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw VideoProcessingError.unexpectedVideoCodec
        }

        // 换音导出时，产物必须真的带音频轨；否则说明音轨在处理中丢失，
        // 不允许静默导出无声视频。
        if case .replace = audio {
            let outputAudio = try await outputAsset.loadTracks(withMediaType: .audio)
            guard !outputAudio.isEmpty else {
                throw VideoProcessingError.missingAudioTrack
            }
        }
        progress(1)
    }

    /// 优先 HEVC：现代设备走硬件编码，比 H.264 最高质量快得多且体积更小；
    /// 设备/资产不支持时回退 H.264 最高质量。
    private static func preferredPreset(for asset: AVAsset) -> String {
        if AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) != nil {
            return AVAssetExportPresetHEVCHighestQuality
        }
        return AVAssetExportPresetHighestQuality
    }

    private static func isSupportedVideoCodec(_ description: CMFormatDescription) -> Bool {
        let subtype = CMFormatDescriptionGetMediaSubType(description)
        return subtype == kCMVideoCodecType_H264 || subtype == kCMVideoCodecType_HEVC
    }
}
