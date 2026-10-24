import CoreGraphics
import XCTest
#if canImport(zeroNetRedact)
@testable import zeroNetRedact
#else
@testable import EditorGeometry
#endif

final class EditorCanvasGeometryTests: XCTestCase {
    func testStrokeContinuesAcrossFoldWithoutChangingMediaCoverage() throws {
        let compact = CGSize(width: 300, height: 200)
        let expanded = CGSize(width: 600, height: 400)
        let points = [EditorCanvasGeometry.normalized(CGPoint(x: 75, y: 50), in: compact),
                      EditorCanvasGeometry.normalized(CGPoint(x: 300, y: 200), in: expanded)]
        let padding = EditorCanvasGeometry.normalized(CGSize(width: 10, height: 10), in: compact)
        let bounds = try XCTUnwrap(EditorCanvasGeometry.strokeBounds(points: points, padding: padding,
                                                                    in: CGSize(width: 1200, height: 800)))
        XCTAssertEqual(bounds.minX, 260, accuracy: 0.0001)
        XCTAssertEqual(bounds.minY, 160, accuracy: 0.0001)
        XCTAssertEqual(bounds.width, 380, accuracy: 0.0001)
        XCTAssertEqual(bounds.height, 280, accuracy: 0.0001)
    }

    func testRepeatedFoldAndKeyboardLayoutsPreservePreviewAndExportAlignment() throws {
        let points = [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.5, y: 0.4)]
        let padding = CGSize(width: 0.02, height: 0.03)
        for size in [CGSize(width: 320, height: 200), CGSize(width: 760, height: 475),
                     CGSize(width: 240, height: 150), CGSize(width: 320, height: 200)] {
            let bounds = try XCTUnwrap(EditorCanvasGeometry.strokeBounds(points: points, padding: padding, in: size))
            XCTAssertEqual(bounds.minX / size.width, 0.18, accuracy: 0.0001)
            XCTAssertEqual(bounds.minY / size.height, 0.27, accuracy: 0.0001)
            XCTAssertEqual(bounds.width / size.width, 0.34, accuracy: 0.0001)
            XCTAssertEqual(bounds.height / size.height, 0.16, accuracy: 0.0001)
        }
    }

    func testSingleTapRetainsBrushAreaAfterResize() throws {
        let bounds = try XCTUnwrap(EditorCanvasGeometry.strokeBounds(points: [CGPoint(x: 0.5, y: 0.5)],
                                  padding: CGSize(width: 0.1, height: 0.05), in: CGSize(width: 1000, height: 2000)))
        XCTAssertEqual(bounds, CGRect(x: 400, y: 900, width: 200, height: 200))
    }

    func testPanUsesOnlyNewTranslationAfterResize() {
        let before = EditorCanvasGeometry.normalized(CGSize(width: 30, height: 20), in: CGSize(width: 300, height: 200))
        // An unchanged cumulative drag contributes zero when the canvas doubles in size.
        let stationary = EditorCanvasGeometry.normalized(CGSize.zero, in: CGSize(width: 600, height: 400))
        let after = EditorCanvasGeometry.normalized(CGSize(width: 60, height: 40), in: CGSize(width: 600, height: 400))
        XCTAssertEqual(before.width + stationary.width + after.width, 0.2, accuracy: 0.0001)
        XCTAssertEqual(before.height + stationary.height + after.height, 0.2, accuracy: 0.0001)
    }

    func testZeroSizedTransitionDoesNotCreateInvalidCoordinates() {
        XCTAssertEqual(EditorCanvasGeometry.normalized(CGPoint(x: 20, y: 30), in: .zero), .zero)
        XCTAssertNil(EditorCanvasGeometry.strokeBounds(points: [.zero], padding: .zero, in: .zero))
        XCTAssertNil(EditorCanvasGeometry.strokeBounds(points: [], padding: .zero, in: CGSize(width: 300, height: 200)))
    }

    func testInspectorDependsOnUsableSpaceInsteadOfDeviceOrOrientation() {
        XCTAssertFalse(EditorWorkspaceLayout.usesInspector(in: CGSize(width: 466, height: 678)))
        XCTAssertTrue(EditorWorkspaceLayout.usesInspector(in: CGSize(width: 951, height: 669)))
        XCTAssertTrue(EditorWorkspaceLayout.usesInspector(in: CGSize(width: 874, height: 337)))
        XCTAssertFalse(EditorWorkspaceLayout.usesInspector(in: CGSize(width: 390, height: 750)))
        XCTAssertTrue(EditorWorkspaceLayout.usesInspector(in: CGSize(width: 750, height: 324)))
        XCTAssertFalse(EditorWorkspaceLayout.usesInspector(in: CGSize(width: 699, height: 600)))
        XCTAssertTrue(EditorWorkspaceLayout.usesInspector(in: CGSize(width: 760, height: 600)))
        XCTAssertTrue(EditorWorkspaceLayout.usesInspector(in: CGSize(width: 1024, height: 1200)))
        XCTAssertFalse(EditorWorkspaceLayout.usesInspector(in: CGSize(width: 820, height: 280)))
        for width in [760.0, 820, 1024, 1366] {
            let size = CGSize(width: width, height: 600)
            XCTAssertGreaterThanOrEqual(EditorWorkspaceLayout.inspectorWidth(in: size), 340)
            XCTAssertLessThanOrEqual(EditorWorkspaceLayout.inspectorWidth(in: size), 380)
            XCTAssertGreaterThan(width - EditorWorkspaceLayout.inspectorWidth(in: size), 350)
        }
    }

    func testVideoColumnsFallBackInNarrowOrKeyboardConstrainedWindows() {
        XCTAssertFalse(EditorWorkspaceLayout.usesVideoColumns(in: CGSize(width: 390, height: 750)))
        XCTAssertFalse(EditorWorkspaceLayout.usesVideoColumns(in: CGSize(width: 667, height: 300)))
        XCTAssertTrue(EditorWorkspaceLayout.usesVideoColumns(in: CGSize(width: 744, height: 1000)))
        XCTAssertTrue(EditorWorkspaceLayout.usesVideoColumns(in: CGSize(width: 820, height: 600)))
        XCTAssertFalse(EditorWorkspaceLayout.usesVideoColumns(in: CGSize(width: 820, height: 280)))
    }
}
