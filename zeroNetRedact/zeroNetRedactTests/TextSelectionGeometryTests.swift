import XCTest
@testable import zeroNetRedact

final class TextSelectionGeometryTests: XCTestCase {
    func testFastSwipeHitsCrossedWordsButNotOutsideDiagonal() {
        let box = CGRect(x: 40, y: 10, width: 20, height: 10)
        XCTAssertTrue(TextSelectionGeometry.intersects(box, from: CGPoint(x: 0, y: 15), to: CGPoint(x: 100, y: 15)))
        XCTAssertFalse(TextSelectionGeometry.intersects(box, from: .zero, to: CGPoint(x: 100, y: 100)))
        XCTAssertTrue(TextSelectionGeometry.intersects(box, from: CGPoint(x: 50, y: 15), to: CGPoint(x: 50, y: 15)))
    }

    func testResizeClampsAndCannotInvert() {
        let box = CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.2)
        for point in [CGPoint(x: -1, y: -1), CGPoint(x: 2, y: 2)] {
            for corner in 0..<2 {
                let result = TextSelectionGeometry.resized(box, corner: corner, to: point)
                XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(result))
                XCTAssertGreaterThan(result.width, 0)
                XCTAssertGreaterThan(result.height, 0)
            }
        }
    }

    func testVisionCoordinatesFlipVerticallyAtDisplaySize() {
        XCTAssertEqual(TextSelectionGeometry.screenRect(CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.2), size: CGSize(width: 100, height: 200)).minY, 40, accuracy: 0.001)
    }

    func testNarrowWordAtEveryEdgeStaysInsideImage() {
        for x in [CGFloat(0), 0.997] {
            for y in [CGFloat(0), 0.997] {
                let box = CGRect(x: x, y: y, width: 0.003, height: 0.003)
                for corner in 0..<2 {
                    for point in [CGPoint.zero, CGPoint(x: 1, y: 1)] {
                        let result = TextSelectionGeometry.resized(box, corner: corner, to: point)
                        XCTAssertGreaterThanOrEqual(result.minX, 0)
                        XCTAssertGreaterThanOrEqual(result.minY, 0)
                        XCTAssertLessThanOrEqual(result.maxX, 1)
                        XCTAssertLessThanOrEqual(result.maxY, 1)
                        XCTAssertGreaterThan(result.width, 0)
                        XCTAssertGreaterThan(result.height, 0)
                    }
                }
            }
        }
    }
}
