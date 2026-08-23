import XCTest

@testable import zeroNetRedact

final class ImageFaceAnalyzerTests: XCTestCase {
    func testRealAnalyzerExecutesVisionRequest() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 320, height: 240),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        }

        do {
            _ = try await ImageFaceAnalyzer().analyze(image: image)
        } catch {
#if targetEnvironment(simulator)
            throw XCTSkip("Vision face inference is unavailable in this simulator: \(error)")
#else
            throw error
#endif
        }
    }

    func testRealAnalyzerHonorsPreexistingCancellation() async {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1_024, height: 1_024),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_024, height: 1_024))
        }
        let task = Task {
            try await ImageFaceAnalyzer().analyze(image: image)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("cancelled analysis should not publish a result")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("unexpected cancellation error: \(error)")
        }
    }

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
