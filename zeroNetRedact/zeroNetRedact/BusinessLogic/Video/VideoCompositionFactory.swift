import AVFoundation
import CoreImage
import Foundation

enum VideoCompositionFactory {
    static func make(
        asset: AVAsset,
        timeline: VideoFaceTimeline,
        sticker: VideoRedactionSticker
    ) -> AVVideoComposition {
        let renderer = VideoRedactionRenderer()
        let composition = AVMutableVideoComposition(
            asset: asset,
            applyingCIFiltersWithHandler: { request in
                let rects = timeline.rects(at: request.compositionTime)
                let output = renderer.render(
                    source: request.sourceImage,
                    normalizedRects: rects,
                    sticker: sticker
                )
                request.finish(with: output, context: nil)
            }
        )
        // 合成帧时长固定 30fps，与分析采样率解耦：长视频降采样（最低 2fps）后，
        // 渲染仍按 30fps 网格查询最近的采样帧，贴纸位置不会出现 0.5s 级跳变
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        return composition
    }
}
