import AVFoundation
import CoreImage
import Foundation

enum VideoCompositionFactory {
    static func make(
        asset: AVAsset,
        timeline: VideoFaceTimeline,
        effect: VideoRedactionEffect
    ) -> AVVideoComposition {
        let renderer = VideoRedactionRenderer()
        let composition = AVMutableVideoComposition(
            asset: asset,
            applyingCIFiltersWithHandler: { request in
                let rects = timeline.rects(at: request.compositionTime)
                let output = renderer.render(
                    source: request.sourceImage,
                    normalizedRects: rects,
                    effect: effect
                )
                request.finish(with: output, context: nil)
            }
        )
        composition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(1, min(60, Int32(timeline.frameRate.rounded()))))
        )
        return composition
    }
}
