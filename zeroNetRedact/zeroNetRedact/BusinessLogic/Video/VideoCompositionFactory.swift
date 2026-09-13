import AVFoundation
import CoreImage
import Foundation

enum VideoCompositionFactory {
    static func make(
        asset: AVAsset,
        timeline: VideoFaceTimeline,
        sticker: VideoRedactionSticker,
        manualRegions: [VideoManualRegion] = [],
        groups: [VideoPersonGroup] = []
    ) -> AVVideoComposition {
        let renderer = VideoRedactionRenderer()
        let composition = AVMutableVideoComposition(
            asset: asset,
            applyingCIFiltersWithHandler: { request in
                let seconds = request.compositionTime.seconds
                var output = request.sourceImage
                if let frame = timeline.frame(at: seconds) {
                    for (index, rect) in frame.normalizedRects.enumerated() {
                        let trackID = frame.trackIDs.indices.contains(index) ? frame.trackIDs[index] : -1
                        let effect = groups.first { $0.trackIDs.contains(trackID) }?.effect ?? sticker.rawValue
                        output = renderer.render(source: output, rect: rect, effect: effect)
                    }
                }
                for region in manualRegions where region.contains(seconds) {
                    output = renderer.render(source: output, rect: region.rect, effect: region.effect)
                }
                request.finish(with: output, context: nil)
            }
        )
        // 合成帧时长固定 30fps，与分析采样率解耦：长视频降采样（最低 2fps）后，
        // 渲染仍按 30fps 网格查询最近的采样帧，贴纸位置不会出现 0.5s 级跳变
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        return composition
    }
}
