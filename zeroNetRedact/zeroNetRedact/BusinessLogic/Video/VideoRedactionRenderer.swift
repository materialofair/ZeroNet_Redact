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
            cache[sticker] = Self.makeStickerImage(sticker)
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
        let background = CIImage(color: CIColor(color: Self.backgroundColor(for: sticker)))
            .cropped(to: rect)
        let artwork = stickerImage
            .transformed(by: transform)
            .clampedToExtent()
            .cropped(to: rect)
        let completedSticker = artwork.composited(over: background).cropped(to: rect)
        return completedSticker.composited(over: source)
    }

    private static func makeStickerImage(_ sticker: VideoRedactionSticker) -> CIImage {
        let size = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            Self.backgroundColor(for: sticker).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            switch sticker {
            case .orangeSmiley:
                Self.drawSmiley(on: cg, size: size, faceColor: UIColor.systemOrange)
            case .blueSmiley:
                Self.drawSmiley(on: cg, size: size, faceColor: UIColor.systemBlue)
            case .sunglasses, .panda, .alien, .heartEyes, .robot, .clown, .lion:
                guard case .asset(let assetName) = sticker.artwork,
                      let artwork = UIImage(named: assetName)
                else {
                    // 资产测试会在发布前拦截缺失文件；运行时仍保留已填充的
                    // 不透明背景，优先保证人脸不会因资源异常而泄露。
                    assertionFailure("Missing bundled sticker artwork: \(sticker.rawValue)")
                    return
                }
                let insetRect = CGRect(origin: .zero, size: size).insetBy(dx: 28, dy: 28)
                artwork.draw(in: Self.aspectFitRect(for: artwork.size, inside: insetRect))
            }
        }
        return CIImage(image: image)
            ?? CIImage(color: CIColor(color: UIColor.systemOrange))
                .cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func aspectFitRect(for source: CGSize, inside target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return target }
        let scale = min(target.width / source.width, target.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: target.midX - size.width / 2,
            y: target.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func backgroundColor(for sticker: VideoRedactionSticker) -> UIColor {
        switch sticker {
        case .orangeSmiley: return .systemOrange
        case .blueSmiley: return .systemBlue
        case .sunglasses: return UIColor(red: 0.78, green: 0.83, blue: 0.91, alpha: 1)
        case .panda: return UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1)
        case .alien: return UIColor(red: 0.72, green: 0.91, blue: 0.79, alpha: 1)
        case .heartEyes: return UIColor(red: 1.00, green: 0.78, blue: 0.82, alpha: 1)
        case .robot: return UIColor(red: 0.72, green: 0.80, blue: 0.86, alpha: 1)
        case .clown: return UIColor(red: 1.00, green: 0.93, blue: 0.78, alpha: 1)
        case .lion: return UIColor(red: 0.96, green: 0.73, blue: 0.35, alpha: 1)
        }
    }

    /// 笑脸：纯色圆形底 + 白色眼白/黑色瞳孔/白色微笑。底图铺满整块，
    /// 保证贴纸整体不透明，不泄露人脸细节。
    private static func drawSmiley(on cg: CGContext, size: CGSize, faceColor: UIColor) {
        faceColor.setFill()
        cg.fill(CGRect(origin: .zero, size: size))

        UIColor.white.setFill()
        cg.fillEllipse(in: CGRect(x: 100, y: 145, width: 92, height: 115))
        cg.fillEllipse(in: CGRect(x: 320, y: 145, width: 92, height: 115))
        UIColor.black.setFill()
        cg.fillEllipse(in: CGRect(x: 132, y: 180, width: 34, height: 50))
        cg.fillEllipse(in: CGRect(x: 346, y: 180, width: 34, height: 50))

        cg.setStrokeColor(UIColor.white.cgColor)
        cg.setLineWidth(34)
        cg.setLineCap(.round)
        cg.addArc(
            center: CGPoint(x: 256, y: 300),
            radius: 105,
            startAngle: .pi * 0.15,
            endAngle: .pi * 0.85,
            clockwise: false
        )
        cg.strokePath()
    }

}
