import AVFoundation
import Foundation

final class VideoExporter {
    func export(
        sourceURL: URL,
        destinationURL: URL,
        timeline: VideoFaceTimeline,
        effect: VideoRedactionEffect,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw VideoProcessingError.missingVideoTrack
        }
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoProcessingError.unableToCreateExporter
        }

        try? FileManager.default.removeItem(at: destinationURL)
        session.outputURL = destinationURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = false
        session.metadata = []
        session.videoComposition = VideoCompositionFactory.make(
            asset: asset,
            timeline: timeline,
            effect: effect
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
        guard descriptions.contains(where: { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw VideoProcessingError.unexpectedVideoCodec
        }
        progress(1)
    }
}
