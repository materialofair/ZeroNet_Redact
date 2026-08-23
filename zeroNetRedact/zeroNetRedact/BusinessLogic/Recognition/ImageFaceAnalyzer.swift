import CoreGraphics
import UIKit
import Vision

enum ImageFaceAnalysisError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        NSLocalizedString("image.face.error.invalidImage", comment: "")
    }
}

final class ImageFaceAnalyzer {
    nonisolated static let analysisMaximumDimension: CGFloat = 2048

    func analyze(image: UIImage) async throws -> [CGRect] {
        guard let source = image.cgImage, image.size.width > 0, image.size.height > 0 else {
            throw ImageFaceAnalysisError.invalidImage
        }
        let imageSize = image.size
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let analysisImage = Self.downsampledImage(
                source,
                maximumDimension: Self.analysisMaximumDimension
            ) ?? source
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: analysisImage, orientation: .up)
            try handler.perform([request])
            try Task.checkCancellation()

            return (request.results ?? [])
                .map {
                    Self.imageRect(
                        fromVisionRect: $0.boundingBox,
                        imageSize: imageSize
                    )
                }
                .filter {
                    $0.origin.x.isFinite && $0.origin.y.isFinite
                        && $0.width.isFinite && $0.height.isFinite
                        && $0.width >= 1 && $0.height >= 1
                }
                .sorted(by: Self.isOrderedBefore)
        }.value
    }

    nonisolated static func imageRect(
        fromVisionRect rect: CGRect,
        imageSize: CGSize,
        expansionScale: CGFloat = 1.3
    ) -> CGRect {
        let expanded = rect.expandedForPrivacy(scale: expansionScale)
        return CGRect(
            x: expanded.minX * imageSize.width,
            y: (1 - expanded.maxY) * imageSize.height,
            width: expanded.width * imageSize.width,
            height: expanded.height * imageSize.height
        ).intersection(CGRect(origin: .zero, size: imageSize))
    }

    private nonisolated static func isOrderedBefore(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let rowTolerance = max(4, min(lhs.height, rhs.height) * 0.35)
        if abs(lhs.midY - rhs.midY) > rowTolerance {
            return lhs.midY < rhs.midY
        }
        return lhs.minX < rhs.minX
    }

    private nonisolated static func downsampledImage(
        _ source: CGImage,
        maximumDimension: CGFloat
    ) -> CGImage? {
        let longest = CGFloat(max(source.width, source.height))
        guard longest > maximumDimension else { return source }
        let ratio = maximumDimension / longest
        let width = max(1, Int((CGFloat(source.width) * ratio).rounded()))
        let height = max(1, Int((CGFloat(source.height) * ratio).rounded()))
        guard let colorSpace = source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
