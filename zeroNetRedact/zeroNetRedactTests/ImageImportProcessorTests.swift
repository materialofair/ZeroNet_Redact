//
//  ImageImportProcessorTests.swift
//  zeroNetRedactTests
//

import UIKit
import XCTest

@testable import zeroNetRedact

final class ImageImportProcessorTests: XCTestCase {

    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.pngData()!
    }

    func testThumbnailMaxDimension200() async throws {
        let processor = ImageImportProcessor()
        let thumbData = try await processor.generateThumbnail(
            from: makeImageData(width: 1170, height: 2532))
        let thumb = UIImage(data: thumbData)!
        XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height), 200)
        XCTAssertEqual(
            thumb.size.width / thumb.size.height, 1170.0 / 2532.0, accuracy: 0.05,
            "保持宽高比")
    }

    func testMetadataMatchesPixelDimensions() {
        let processor = ImageImportProcessor()
        let metadata = processor.extractMetadata(from: makeImageData(width: 640, height: 480))
        XCTAssertEqual(metadata["width"] as? Int, 640)
        XCTAssertEqual(metadata["height"] as? Int, 480)
        XCTAssertEqual(metadata["orientation"] as? Int, UIImage.Orientation.up.rawValue)
    }

    func testMetadataGarbageDataReturnsEmpty() {
        let processor = ImageImportProcessor()
        XCTAssertTrue(processor.extractMetadata(from: Data([0xFF, 0x00])).isEmpty)
    }
}
