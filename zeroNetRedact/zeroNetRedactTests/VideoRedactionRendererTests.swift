import CoreImage
import XCTest
@testable import zeroNetRedact

final class VideoRedactionRendererTests: XCTestCase {
    private let context = CIContext(options: [.useSoftwareRenderer: true])

    func testCartoonStickerIsOpaqueAndChangesOnlyCoveredArea() throws {
        let extent = CGRect(x: 0, y: 0, width: 200, height: 200)
        let source = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
            .cropped(to: extent)
        let rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        let output = VideoRedactionRenderer().render(
            source: source,
            normalizedRects: [rect],
            effect: .cartoonSticker
        )

        let inside = try pixel(output, x: 100, y: 100)
        let outside = try pixel(output, x: 10, y: 10)
        XCTAssertEqual(inside[3], 255)
        XCTAssertNotEqual(inside, outside)
        XCTAssertEqual(outside, [25, 51, 204, 255])
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
