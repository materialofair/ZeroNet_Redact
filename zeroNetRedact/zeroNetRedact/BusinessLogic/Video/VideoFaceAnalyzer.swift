import AVFoundation
import Foundation
import Vision

final class VideoFaceAnalyzer {
    func analyze(
        url: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> VideoFaceTimeline {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                throw VideoProcessingError.invalidDuration
            }
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw VideoProcessingError.missingVideoTrack
            }
            let sourceRate = Double(try await track.load(.nominalFrameRate))
            let frameRate = min(max(sourceRate, 1), 30)
            let frameCount = max(1, Int(ceil(durationSeconds * frameRate)))

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: CMTimeScale(frameRate * 2))
            generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore

            var frames: [VideoFaceFrame] = []
            frames.reserveCapacity(frameCount)
            var smoother = FaceTrackSmoother()

            for index in 0..<frameCount {
                try Task.checkCancellation()
                let seconds = min(Double(index) / frameRate, durationSeconds)
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                var actualTime = CMTime.zero
                let image: CGImage
                do {
                    image = try generator.copyCGImage(at: time, actualTime: &actualTime)
                } catch {
                    let carried = smoother.update(with: [])
                    frames.append(VideoFaceFrame(seconds: seconds, normalizedRects: carried))
                    progress(Double(index + 1) / Double(frameCount))
                    continue
                }

                let request = VNDetectFaceRectanglesRequest()
                let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
                try handler.perform([request])
                let detections = (request.results ?? []).map {
                    $0.boundingBox.expandedForPrivacy()
                }
                let smoothed = smoother.update(with: detections)
                frames.append(VideoFaceFrame(seconds: seconds, normalizedRects: smoothed))
                progress(Double(index + 1) / Double(frameCount))
            }

            return VideoFaceTimeline(
                frames: frames,
                frameRate: frameRate,
                totalUniqueFaces: smoother.createdTrackCount
            )
        }.value
    }
}
