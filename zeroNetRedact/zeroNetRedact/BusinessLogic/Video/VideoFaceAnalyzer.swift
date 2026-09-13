import CoreGraphics
import AVFoundation
import Foundation
import Vision
import OSLog

final class VideoFaceAnalyzer {
    /// 人脸检测的输入长边上限（像素）。逐帧检测不需要原分辨率：
    /// 4K 帧缩小到 1280 后单帧内存约下降 10 倍、检测更快，
    /// 且输出是归一化坐标，不影响后续贴纸定位。
    private static let analysisMaximumDimension: CGFloat = 1280

    /// 沿用现有采样预算：30fps × 4 分钟，长视频最低 2fps。
    /// 这不是严格帧数上限；稀疏采样对快速移动人脸仍需人工复核。
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
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let started = CFAbsoluteTimeGetCurrent()
            var readSeconds = 0.0
            var visionSeconds = 0.0
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
            // 按时长动态降采样，最低 2fps。
            let effectiveRate = min(
                frameRate, max(2.0, Self.analysisMaxFrameCount / durationSeconds))
            let rawFrameCount = durationSeconds * effectiveRate
            guard rawFrameCount.isFinite else {
                throw VideoProcessingError.invalidDuration
            }
            let frameCount = max(1, Int(ceil(rawFrameCount)))

            // 顺序解码一次；composition 负责旋转、缩放和采样，避免逐帧随机截图。
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderVideoCompositionOutput(
                videoTracks: [track],
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            )
            output.alwaysCopiesSampleData = false
            output.videoComposition = try await Self.analysisComposition(
                track: track, duration: duration, frameRate: effectiveRate
            )
            guard reader.canAdd(output) else {
                throw VideoProcessingError.unableToCreateComposition
            }
            reader.add(output)
            guard reader.startReading() else {
                throw reader.error ?? VideoProcessingError.unableToCreateComposition
            }
            defer { reader.cancelReading() }
            let request = VNDetectFaceRectanglesRequest()
            #if targetEnvironment(simulator)
            // 模拟器没有真机的推理硬件；仅模拟器使用 CPU 执行 Vision。
            request.usesCPUOnly = true
            #endif

            var frames: [VideoFaceFrame] = []
            frames.reserveCapacity(frameCount)
            var smoother = FaceTrackSmoother(
                maximumMissedFrames: max(
                    2, Int((Self.missedFramesTimeWindow * effectiveRate).rounded(.up))))

            var lastReportedPercent = -1
            // 剩余时间预估：每帧耗时的指数移动平均 × 剩余帧数
            var perFrameEMA: TimeInterval = 0
            while true {
                try Task.checkCancellation()
                let frameStart = CFAbsoluteTimeGetCurrent()
                // 限制每帧解码/Vision 临时对象的生命周期。
                let result: VideoFaceFrame? = try autoreleasepool {
                    let readStart = CFAbsoluteTimeGetCurrent()
                    guard let sample = output.copyNextSampleBuffer() else { return nil }
                    readSeconds += CFAbsoluteTimeGetCurrent() - readStart
                    guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
                        throw VideoProcessingError.unableToCreateThumbnail
                    }
                    let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                    let visionStart = CFAbsoluteTimeGetCurrent()
                    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
                    // 检测失败必须中止，不能把失败当作“没有人脸”。
                    try handler.perform([request])
                    visionSeconds += CFAbsoluteTimeGetCurrent() - visionStart
                    return VideoFaceFrame(seconds: seconds, normalizedRects: (request.results ?? []).map {
                        $0.boundingBox.expandedForPrivacy()
                    })
                }
                guard let result else { break }
                let seconds = result.seconds
                let detections = result.normalizedRects
                let smoothed = smoother.update(with: detections)
                frames.append(VideoFaceFrame(seconds: seconds, normalizedRects: smoothed, trackIDs: smoother.tracks.map(\.id)))

                let frameCost = CFAbsoluteTimeGetCurrent() - frameStart
                perFrameEMA = perFrameEMA == 0 ? frameCost : perFrameEMA * 0.8 + frameCost * 0.2

                // 进度只按整百分比上报，避免每帧向主线程投递一个 Task。
                let fraction = min(Double(frames.count) / Double(frameCount), 0.99)
                let percent = Int(fraction * 100)
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    progress(fraction)
                    eta(max(0, perFrameEMA * Double(max(0, frameCount - frames.count))))
                }
            }
            try Task.checkCancellation()
            guard reader.status == .completed else {
                throw reader.error ?? VideoProcessingError.unableToCreateThumbnail
            }
            guard !frames.isEmpty else { throw VideoProcessingError.unableToCreateThumbnail }
            Logger(subsystem: "zeroNetRedact", category: "VideoPerformance").info(
                "analysis frames=\(frames.count) readSeconds=\(readSeconds) visionSeconds=\(visionSeconds) totalSeconds=\(CFAbsoluteTimeGetCurrent() - started)"
            )
            progress(1)
            eta(nil)

            return VideoFaceTimeline(
                frames: frames,
                frameRate: effectiveRate,
                totalUniqueFaces: smoother.createdTrackCount
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// 输出坐标与预览一致，包括竖屏、镜像和非零平移。
    static func analysisComposition(
        track: AVAssetTrack,
        duration: CMTime,
        frameRate: Double
    ) async throws -> AVVideoComposition {
        let size = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(preferred).standardized
        guard bounds.width > 0, bounds.height > 0 else {
            throw VideoProcessingError.unableToCreateComposition
        }
        let scale = min(1, analysisMaximumDimension / max(bounds.width, bounds.height))
        let renderSize = CGSize(
            width: max(2, (bounds.width * scale / 2).rounded(.down) * 2),
            height: max(2, (bounds.height * scale / 2).rounded(.down) * 2)
        )
        let transform = preferred
            .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(
                scaleX: renderSize.width / bounds.width, y: renderSize.height / bounds.height
            ))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(seconds: 1 / frameRate, preferredTimescale: 60000)
        composition.instructions = [instruction]
        return composition
    }
}
