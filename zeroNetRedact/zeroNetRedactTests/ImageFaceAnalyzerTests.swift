import XCTest

@testable import zeroNetRedact

final class ImageFaceAnalyzerTests: XCTestCase {
    func testVisionRectConvertsToUIKitImageSpace() {
        let result = ImageFaceAnalyzer.imageRect(
            fromVisionRect: CGRect(x: 0.10, y: 0.70, width: 0.20, height: 0.10),
            imageSize: CGSize(width: 1000, height: 500),
            expansionScale: 1
        )
        XCTAssertEqual(result.origin.x, 100, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 100, accuracy: 0.001)
        XCTAssertEqual(result.width, 200, accuracy: 0.001)
        XCTAssertEqual(result.height, 50, accuracy: 0.001)
    }

    func testPrivacyExpansionClampsAtImageEdges() {
        let result = ImageFaceAnalyzer.imageRect(
            fromVisionRect: CGRect(x: 0, y: 0.90, width: 0.10, height: 0.10),
            imageSize: CGSize(width: 1000, height: 500)
        )
        XCTAssertEqual(result.minX, 0, accuracy: 0.001)
        XCTAssertEqual(result.minY, 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(result.maxX, 1000)
        XCTAssertLessThanOrEqual(result.maxY, 500)
    }

    func testIntersectionOverUnion() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(rect.intersectionOverUnion(with: rect), 1, accuracy: 0.0001)
        XCTAssertEqual(
            rect.intersectionOverUnion(with: CGRect(x: 20, y: 20, width: 10, height: 10)),
            0,
            accuracy: 0.0001
        )
    }
}
