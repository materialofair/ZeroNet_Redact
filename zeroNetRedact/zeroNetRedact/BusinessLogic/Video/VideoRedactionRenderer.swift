import CoreImage
import UIKit

final class VideoRedactionRenderer {
    /// 贴纸图在 init 时全部预生成，之后只读。
    /// AVMutableVideoComposition 的 CIFilter 回调由 AVFoundation 在后台队列
    /// （可能并发）调用，若沿用"懒加载 + 可变字典"缓存，Release 优化下会
    /// 因数据竞争崩溃；预生成后 render 为纯只读操作，天然线程安全。
    private let stickerCache: [VideoRedactionSticker: CIImage]

    init() {
        var cache: [VideoRedactionSticker: CIImage] = [:]
        cache.reserveCapacity(VideoRedactionSticker.allCases.count)
        for sticker in VideoRedactionSticker.allCases {
            cache[sticker] = FaceStickerRenderer.ciImage(for: sticker)
        }
        stickerCache = cache
    }

    func render(
        source: CIImage,
        normalizedRects: [CGRect],
        sticker: VideoRedactionSticker
    ) -> CIImage {
        normalizedRects.reduce(source) { image, normalizedRect in
            let rect = standardizedPixelRect(for: normalizedRect, in: source.extent)
            guard rect.width >= 1, rect.height >= 1 else { return image }
            return applySticker(to: image, rect: rect, sticker: sticker)
        }.cropped(to: source.extent)
    }

    /// 所有渲染和测试共用同一像素边界：向外取整可以略微扩大遮挡，
    /// 但不会在脸框边缘留下半透明采样像素。
    func standardizedPixelRect(for normalized: CGRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + normalized.minX * extent.width,
            y: extent.minY + normalized.minY * extent.height,
            width: normalized.width * extent.width,
            height: normalized.height * extent.height
        ).integral.intersection(extent.integral)
    }

    private func applySticker(
        to source: CIImage,
        rect: CGRect,
        sticker: VideoRedactionSticker
    ) -> CIImage {
        guard let stickerImage = stickerCache[sticker] else { return source }
        let transform = CGAffineTransform(
            translationX: rect.minX,
            y: rect.minY
        ).scaledBy(
            x: rect.width / stickerImage.extent.width,
            y: rect.height / stickerImage.extent.height
        )
        let artwork = stickerImage
            .transformed(by: transform)
            .clampedToExtent()
            .cropped(to: rect)
        return artwork.composited(over: source)
    }
}
