import CoreImage
import UIKit

final class VideoRedactionRenderer {
    private lazy var stickerImage: CIImage = makeStickerImage()

    func render(
        source: CIImage,
        normalizedRects: [CGRect],
        effect: VideoRedactionEffect
    ) -> CIImage {
        normalizedRects.reduce(source) { image, normalizedRect in
            let rect = pixelRect(for: normalizedRect, in: source.extent)
            guard rect.width >= 1, rect.height >= 1 else { return image }
            switch effect {
            case .strongBlur:
                return applyBlur(to: image, rect: rect)
            case .cartoonSticker:
                return applySticker(to: image, rect: rect)
            }
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

    private func applyBlur(to source: CIImage, rect: CGRect) -> CIImage {
        let radius = max(24, min(rect.width, rect.height) * 0.22)
        let region = source.cropped(to: rect.insetBy(dx: -radius * 2, dy: -radius * 2))
        let blurred = region
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: rect)
        return blurred.composited(over: source)
    }

    private func applySticker(to source: CIImage, rect: CGRect) -> CIImage {
        let transform = CGAffineTransform(
            translationX: rect.minX,
            y: rect.minY
        ).scaledBy(
            x: rect.width / stickerImage.extent.width,
            y: rect.height / stickerImage.extent.height
        )
        return stickerImage.transformed(by: transform).composited(over: source)
    }

    private func makeStickerImage() -> CIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            UIColor.systemOrange.setFill()
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
        return CIImage(image: image)
            ?? CIImage(color: CIColor(color: UIColor.systemOrange))
                .cropped(to: CGRect(origin: .zero, size: size))
    }
}
