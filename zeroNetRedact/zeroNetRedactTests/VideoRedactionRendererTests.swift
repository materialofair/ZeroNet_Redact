import CoreImage
import XCTest
@testable import zeroNetRedact

final class VideoRedactionRendererTests: XCTestCase {
    private let context = CIContext(options: [.useSoftwareRenderer: true])

    func testEveryStickerIsSourceIndependentAcrossEntireCoveredArea() throws {
        for sticker in VideoRedactionSticker.allCases {
            let extent = CGRect(x: 0, y: 0, width: 200, height: 200)
            let sourceA = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
                .cropped(to: extent)
            let sourceB = CIImage(color: CIColor(red: 0.9, green: 0.8, blue: 0.1, alpha: 1))
                .cropped(to: extent)
            let normalizedRect = CGRect(x: 0.347, y: 0.353, width: 0.301, height: 0.297)
            let renderer = VideoRedactionRenderer()
            let covered = renderer.standardizedPixelRect(for: normalizedRect, in: extent)

            let outputA = renderer.render(
                source: sourceA,
                normalizedRects: [normalizedRect],
                sticker: sticker
            )
            let outputB = renderer.render(
                source: sourceB,
                normalizedRects: [normalizedRect],
                sticker: sticker
            )

            let sourceABytes = pixels(sourceA, extent: extent)
            let sourceBBytes = pixels(sourceB, extent: extent)
            let outputABytes = pixels(outputA, extent: extent)
            let outputBBytes = pixels(outputB, extent: extent)

            var sourceDependentPixel: CGPoint?
            var changedOutsidePixel: CGPoint?
            var coveredColors = Set<UInt32>()
            for y in 0..<Int(extent.height) {
                for x in 0..<Int(extent.width) {
                    let offset = (y * Int(extent.width) + x) * 4
                    if covered.contains(CGPoint(x: x, y: y)) {
                        coveredColors.insert(rgbaValue(outputABytes, at: offset))
                        if !rgbaEqual(outputABytes, outputBBytes, at: offset) {
                            sourceDependentPixel = CGPoint(x: x, y: y)
                        }
                    } else if !rgbaEqual(outputABytes, sourceABytes, at: offset)
                        || !rgbaEqual(outputBBytes, sourceBBytes, at: offset) {
                        changedOutsidePixel = CGPoint(x: x, y: y)
                    }
                }
            }
            XCTAssertNil(
                sourceDependentPixel,
                "\(sticker.rawValue): 遮挡区像素 \(String(describing: sourceDependentPixel)) 不应依赖原视频"
            )
            XCTAssertNil(
                changedOutsidePixel,
                "\(sticker.rawValue): 遮挡区外像素 \(String(describing: changedOutsidePixel)) 应保持原样"
            )
            XCTAssertGreaterThan(
                coveredColors.count,
                1,
                "\(sticker.rawValue): 遮挡区不能退化成只有纯色背景"
            )
        }
    }

    private func rgbaValue(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    private func rgbaEqual(_ lhs: [UInt8], _ rhs: [UInt8], at offset: Int) -> Bool {
        lhs[offset] == rhs[offset]
            && lhs[offset + 1] == rhs[offset + 1]
            && lhs[offset + 2] == rhs[offset + 2]
            && lhs[offset + 3] == rhs[offset + 3]
    }

    private func pixels(_ image: CIImage, extent: CGRect) -> [UInt8] {
        let rowBytes = Int(extent.width) * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * Int(extent.height))
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: rowBytes,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes
    }
}
