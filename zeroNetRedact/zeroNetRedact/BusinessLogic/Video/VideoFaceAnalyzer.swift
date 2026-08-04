import CoreGraphics
import AVFoundation
import Foundation
import Vision

final class VideoFaceAnalyzer {
    /// 人脸检测的输入长边上限（像素）。逐帧检测不需要原分辨率：
    /// 4K 帧缩小到 1280 后单帧内存约下降 10 倍、检测更快，
    /// 且输出是归一化坐标，不影响后续贴纸定位。
    private static let analysisMaximumDimension: CGFloat = 1280

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
            // nominalFrameRate 可能为 0 或异常值；统一回退到 30fps，
            // 避免 NaN/Inf 进入后面的 Int 转换触发运行时崩溃。
            let sourceRate = Double(try await track.load(.nominalFrameRate))
            let safeRate = sourceRate.isFinite && sourceRate > 0 ? sourceRate : 30
            let frameRate = min(max(safeRate, 1), 30)
            let rawFrameCount = durationSeconds * frameRate
            guard rawFrameCount.isFinite else {
                throw VideoProcessingError.invalidDuration
            }
            let frameCount = max(1, Int(ceil(rawFrameCount)))

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(
                width: Self.analysisMaximumDimension,
                height: Self.analysisMaximumDimension
            )
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: CMTimeScale(frameRate * 2))
            generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore

            var frames: [VideoFaceFrame] = []
            frames.reserveCapacity(frameCount)
            var smoother = FaceTrackSmoother()

            var lastReportedPercent = -1
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let seconds = min(Double(index) / frameRate, durationSeconds)
                // 每帧处理放进 autoreleasepool：AVAssetImageGenerator 与 Vision
                // 会生成大量自动释放对象，长视频循环中不显式排空会持续累积内存，
                // 最终触发系统 jetsam 强杀（表现为闪退）。
                let detections = autoreleasepool {
                    Self.detectFaces(in: generator, at: seconds)
                } ?? []
                let smoothed = smoother.update(with: detections)
                frames.append(VideoFaceFrame(seconds: seconds, normalizedRects: smoothed))

                // 进度只按整百分比上报，避免每帧向主线程投递一个 Task。
                let percent = Int((Double(index + 1) / Double(frameCount)) * 100)
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    progress(Double(index + 1) / Double(frameCount))
                }
            }

            return VideoFaceTimeline(
                frames: frames,
                frameRate: frameRate,
                totalUniqueFaces: smoother.createdTrackCount
            )
        }.value
    }

    /// 提取一帧并检测人脸矩形；任一环节失败返回 nil（上层沿用上一帧结果）。
    private static func detectFaces(
        in generator: AVAssetImageGenerator,
        at seconds: Double
    ) -> [CGRect]? {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        var actualTime = CMTime.zero
        let image: CGImage
        do {
            image = try generator.copyCGImage(at: time, actualTime: &actualTime)
        } catch {
            return nil
        }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return (request.results ?? []).map {
            $0.boundingBox.expandedForPrivacy()
        }
    }
}
