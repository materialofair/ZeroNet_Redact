import CoreGraphics
import AVFoundation
import Foundation
import Vision

final class VideoFaceAnalyzer {
    /// 人脸检测的输入长边上限（像素）。逐帧检测不需要原分辨率：
    /// 4K 帧缩小到 1280 后单帧内存约下降 10 倍、检测更快，
    /// 且输出是归一化坐标，不影响后续贴纸定位。
    private static let analysisMaximumDimension: CGFloat = 1280

    /// 采样总帧数上限：30fps × 4 分钟。更长的视频按时长降采样（最低 2fps）：
    /// 人脸位置变化缓慢，稀疏采样 + 平滑器足以保证遮盖质量。
    /// 此前 1 小时视频约需 10.8 万帧 Vision 分析，降采样后约 7200 帧。
    private static let analysisMaxFrameCount = 7200.0

    /// 降采样时平滑器"容忍丢失帧数"换算成真实时间的窗口（秒）。
    /// FaceTrackSmoother 的 maximumMissedFrames 以采样帧为单位，
    /// 采样变稀后必须按时间换算，否则同一 5 帧窗口代表的真实时间被拉长。
    private static let missedFramesTimeWindow: Double = 0.3

    func analyze(
        url: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in },
        eta: @escaping @Sendable (TimeInterval?) -> Void = { _ in }
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
            // 按时长动态降采样：总帧数封顶 analysisMaxFrameCount，最低 2fps
            let effectiveRate = min(
                frameRate, max(2.0, Self.analysisMaxFrameCount / durationSeconds))
            let rawFrameCount = durationSeconds * effectiveRate
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
            generator.requestedTimeToleranceBefore = CMTime(
                value: 1, timescale: CMTimeScale(effectiveRate * 2))
            generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore

            var frames: [VideoFaceFrame] = []
            frames.reserveCapacity(frameCount)
            var smoother = FaceTrackSmoother(
                maximumMissedFrames: max(
                    2, Int((Self.missedFramesTimeWindow * effectiveRate).rounded(.up))))

            var lastReportedPercent = -1
            // 剩余时间预估：每帧耗时的指数移动平均 × 剩余帧数
            var perFrameEMA: TimeInterval = 0
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let frameStart = CFAbsoluteTimeGetCurrent()
                let seconds = min(Double(index) / effectiveRate, durationSeconds)
                // 每帧处理放进 autoreleasepool：AVAssetImageGenerator 与 Vision
                // 会生成大量自动释放对象，长视频循环中不显式排空会持续累积内存，
                // 最终触发系统 jetsam 强杀（表现为闪退）。
                let detections = autoreleasepool {
                    Self.detectFaces(in: generator, at: seconds)
                } ?? []
                let smoothed = smoother.update(with: detections)
                frames.append(VideoFaceFrame(seconds: seconds, normalizedRects: smoothed))

                let frameCost = CFAbsoluteTimeGetCurrent() - frameStart
                perFrameEMA = perFrameEMA == 0 ? frameCost : perFrameEMA * 0.8 + frameCost * 0.2

                // 进度只按整百分比上报，避免每帧向主线程投递一个 Task。
                let percent = Int((Double(index + 1) / Double(frameCount)) * 100)
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    progress(Double(index + 1) / Double(frameCount))
                    eta(max(0, perFrameEMA * Double(frameCount - index - 1)))
                }
            }
            eta(nil)

            return VideoFaceTimeline(
                frames: frames,
                frameRate: effectiveRate,
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
