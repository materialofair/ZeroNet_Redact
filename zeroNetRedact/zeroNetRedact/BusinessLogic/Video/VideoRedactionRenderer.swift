import CoreImage
import UIKit

final class VideoRedactionRenderer {
    private var stickerCache: [VideoRedactionSticker: CIImage] = [:]

    func render(
        source: CIImage,
        normalizedRects: [CGRect],
        sticker: VideoRedactionSticker
    ) -> CIImage {
        normalizedRects.reduce(source) { image, normalizedRect in
            let rect = pixelRect(for: normalizedRect, in: source.extent)
            guard rect.width >= 1, rect.height >= 1 else { return image }
            return applySticker(to: image, rect: rect, sticker: sticker)
        }.cropped(to: source.extent)
    }

    private func pixelRect(for normalized: CGRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + normalized.minX * extent.width,
            y: extent.minY + normalized.minY * extent.height,
            width: normalized.width * extent.width,
            height: normalized.height * extent.height
        ).intersection(extent)
    }

    private func applySticker(
        to source: CIImage,
        rect: CGRect,
        sticker: VideoRedactionSticker
    ) -> CIImage {
        let stickerImage = cachedStickerImage(for: sticker)
        let transform = CGAffineTransform(
            translationX: rect.minX,
            y: rect.minY
        ).scaledBy(
            x: rect.width / stickerImage.extent.width,
            y: rect.height / stickerImage.extent.height
        )
        return stickerImage.transformed(by: transform).composited(over: source)
    }

    private func cachedStickerImage(for sticker: VideoRedactionSticker) -> CIImage {
        if let cached = stickerCache[sticker] {
            return cached
        }
        let image = makeStickerImage(sticker)
        stickerCache[sticker] = image
        return image
    }

    private func makeStickerImage(_ sticker: VideoRedactionSticker) -> CIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            switch sticker {
            case .orangeSmiley:
                Self.drawSmiley(on: cg, size: size, faceColor: UIColor.systemOrange)
            case .blueSmiley:
                Self.drawSmiley(on: cg, size: size, faceColor: UIColor.systemBlue)
            case .sunglasses:
                Self.drawSunglasses(on: cg, size: size)
            case .panda:
                Self.drawPanda(on: cg, size: size)
            case .alien:
                Self.drawAlien(on: cg, size: size)
            }
        }
        return CIImage(image: image)
            ?? CIImage(color: CIColor(color: UIColor.systemOrange))
                .cropped(to: CGRect(origin: .zero, size: size))
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

    /// 墨镜：灰色圆形底 + 黑色一体墨镜 + 镜片高光 + 白色微笑。
    private static func drawSunglasses(on cg: CGContext, size: CGSize) {
        UIColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1).setFill()
        cg.fill(CGRect(origin: .zero, size: size))

        UIColor.black.setFill()
        let lensRect = CGRect(x: 60, y: 130, width: 392, height: 140)
        UIBezierPath(roundedRect: lensRect, cornerRadius: 40).fill()
        cg.fill(CGRect(x: 236, y: 190, width: 40, height: 22))

        UIColor.white.setFill()
        cg.fillEllipse(in: CGRect(x: 110, y: 160, width: 30, height: 46))
        cg.fillEllipse(in: CGRect(x: 330, y: 160, width: 30, height: 46))

        cg.setStrokeColor(UIColor.white.cgColor)
        cg.setLineWidth(30)
        cg.setLineCap(.round)
        cg.addArc(
            center: CGPoint(x: 256, y: 350),
            radius: 82,
            startAngle: .pi * 0.18,
            endAngle: .pi * 0.82,
            clockwise: false
        )
        cg.strokePath()
    }

    /// 熊猫：黑色耳朵垫底，白色圆脸覆盖，黑色眼斑 + 白瞳 + 黑鼻 + 微笑。
    private static func drawPanda(on cg: CGContext, size: CGSize) {
        UIColor.black.setFill()
        cg.fillEllipse(in: CGRect(x: 70, y: 60, width: 150, height: 150))
        cg.fillEllipse(in: CGRect(x: 292, y: 60, width: 150, height: 150))

        UIColor.white.setFill()
        cg.fill(CGRect(origin: .zero, size: size))

        UIColor.black.setFill()
        cg.fillEllipse(in: CGRect(x: 100, y: 175, width: 128, height: 118))
        cg.fillEllipse(in: CGRect(x: 284, y: 175, width: 128, height: 118))
        UIColor.white.setFill()
        cg.fillEllipse(in: CGRect(x: 132, y: 215, width: 40, height: 52))
        cg.fillEllipse(in: CGRect(x: 340, y: 215, width: 40, height: 52))

        UIColor.black.setFill()
        cg.fillEllipse(in: CGRect(x: 236, y: 300, width: 40, height: 26))

        cg.setStrokeColor(UIColor.black.cgColor)
        cg.setLineWidth(22)
        cg.setLineCap(.round)
        cg.addArc(
            center: CGPoint(x: 256, y: 340),
            radius: 60,
            startAngle: .pi * 0.2,
            endAngle: .pi * 0.8,
            clockwise: false
        )
        cg.strokePath()
    }

    /// 外星人：绿色圆脸 + 两根触角 + 大黑眼 + 微笑。
    private static func drawAlien(on cg: CGContext, size: CGSize) {
        UIColor.systemGreen.setFill()
        cg.fill(CGRect(origin: .zero, size: size))

        cg.setStrokeColor(UIColor.black.cgColor)
        cg.setLineWidth(18)
        cg.setLineCap(.round)
        cg.move(to: CGPoint(x: 176, y: 60))
        cg.addLine(to: CGPoint(x: 140, y: 110))
        cg.move(to: CGPoint(x: 336, y: 60))
        cg.addLine(to: CGPoint(x: 372, y: 110))
        cg.strokePath()

        UIColor.black.setFill()
        cg.fillEllipse(in: CGRect(x: 116, y: 76, width: 48, height: 48))
        cg.fillEllipse(in: CGRect(x: 348, y: 76, width: 48, height: 48))
        cg.fillEllipse(in: CGRect(x: 120, y: 170, width: 84, height: 140))
        cg.fillEllipse(in: CGRect(x: 308, y: 170, width: 84, height: 140))

        cg.setStrokeColor(UIColor.black.cgColor)
        cg.setLineWidth(20)
        cg.setLineCap(.round)
        cg.addArc(
            center: CGPoint(x: 256, y: 330),
            radius: 48,
            startAngle: .pi * 0.25,
            endAngle: .pi * 0.75,
            clockwise: false
        )
        cg.strokePath()
    }
}
