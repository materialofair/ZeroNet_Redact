import CoreImage
import XCTest
@testable import zeroNetRedact

final class VideoRedactionRendererTests: XCTestCase {
    private let context = CIContext(options: [.useSoftwareRenderer: true])

    func testEveryStickerIsOpaqueAndChangesOnlyCoveredArea() throws {
        for sticker in VideoRedactionSticker.allCases {
            let extent = CGRect(x: 0, y: 0, width: 200, height: 200)
            let left = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200))
            let right = CIImage(color: CIColor(red: 0.9, green: 0.8, blue: 0.1, alpha: 1))
                .cropped(to: CGRect(x: 100, y: 0, width: 100, height: 200))
            // 左蓝右黄；贴纸区（[70,70,60,60]）横跨 100px 色块分界线，
            // 但离 (10,10) 足够远，保证外部采样点不在贴纸区域内。
            let source = right.composited(over: left).cropped(to: extent)
            let rect = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)

            let output = VideoRedactionRenderer().render(
                source: source,
                normalizedRects: [rect],
                sticker: sticker
            )

            let inside = try pixel(output, x: 100, y: 100)
            let outside = try pixel(output, x: 10, y: 10)
            XCTAssertEqual(
                outside, [25, 51, 204, 255],
                "\(sticker.rawValue): 贴纸区域外应保持原图不变"
            )
            XCTAssertEqual(inside[3], 255, "\(sticker.rawValue): 贴纸覆盖区应不透明")
            XCTAssertNotEqual(
                inside, [230, 204, 26, 255],
                "\(sticker.rawValue): 贴纸覆盖区应被替换为贴纸内容"
            )
            XCTAssertNotEqual(inside, outside, "\(sticker.rawValue): 贴纸覆盖区应与原图不同")
        }
    }

    private func pixel(_ image: CIImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes
    }
}
