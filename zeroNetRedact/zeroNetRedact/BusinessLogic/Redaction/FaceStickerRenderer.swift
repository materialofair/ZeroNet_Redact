import CoreImage
import UIKit

/// 生成图片/视频共用的不透明贴纸底图。
enum FaceStickerRenderer {
    static func image(
        for sticker: FaceRedactionSticker,
        size: CGSize = CGSize(width: 512, height: 512)
    ) -> UIImage {
        let safeSize = CGSize(width: max(1, size.width), height: max(1, size.height))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: safeSize, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: safeSize)
            backgroundColor(for: sticker).setFill()
            context.fill(bounds)

            switch sticker {
            case .orangeSmiley:
                drawSmiley(on: context.cgContext, bounds: bounds, faceColor: .systemOrange)
            case .blueSmiley:
                drawSmiley(on: context.cgContext, bounds: bounds, faceColor: .systemBlue)
            case .sunglasses, .panda, .alien, .heartEyes, .robot, .clown, .lion:
                guard case .asset(let assetName) = sticker.artwork,
                    let artwork = UIImage(named: assetName)
                else {
                    assertionFailure("Missing bundled sticker artwork: \(sticker.rawValue)")
                    return
                }
                let inset = min(safeSize.width, safeSize.height) * (28.0 / 512.0)
                artwork.draw(in: aspectFitRect(for: artwork.size, inside: bounds.insetBy(dx: inset, dy: inset)))
            }
        }
    }

    static func ciImage(for sticker: FaceRedactionSticker) -> CIImage {
        CIImage(image: image(for: sticker))
            ?? CIImage(color: CIColor(color: backgroundColor(for: sticker)))
                .cropped(to: CGRect(x: 0, y: 0, width: 512, height: 512))
    }

    static func backgroundColor(for sticker: FaceRedactionSticker) -> UIColor {
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

    private static func aspectFitRect(for source: CGSize, inside target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return target }
        let scale = min(target.width / source.width, target.height / source.height)
        let fitted = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: target.midX - fitted.width / 2,
            y: target.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private static func drawSmiley(
        on context: CGContext,
        bounds: CGRect,
        faceColor: UIColor
    ) {
        context.saveGState()
        context.translateBy(x: bounds.minX, y: bounds.minY)
        context.scaleBy(x: bounds.width / 512, y: bounds.height / 512)
        faceColor.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        UIColor.white.setFill()
        context.fillEllipse(in: CGRect(x: 100, y: 145, width: 92, height: 115))
        context.fillEllipse(in: CGRect(x: 320, y: 145, width: 92, height: 115))
        UIColor.black.setFill()
        context.fillEllipse(in: CGRect(x: 132, y: 180, width: 34, height: 50))
        context.fillEllipse(in: CGRect(x: 346, y: 180, width: 34, height: 50))
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(34)
        context.setLineCap(.round)
        context.addArc(
            center: CGPoint(x: 256, y: 300),
            radius: 105,
            startAngle: .pi * 0.15,
            endAngle: .pi * 0.85,
            clockwise: false
        )
        context.strokePath()
        context.restoreGState()
    }
}
