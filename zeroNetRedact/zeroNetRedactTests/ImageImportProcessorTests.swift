//
//  ImageImportProcessorTests.swift
//  zeroNetRedactTests
//

import ImageIO
import UIKit
import UniformTypeIdentifiers
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

    /// 锁定行为:小于 200px 的源图缩略图保持原尺寸(ImageIO 不放大)
    func testThumbnailSmallImageNotUpscaled() async throws {
        let processor = ImageImportProcessor()
        let thumbData = try await processor.generateThumbnail(
            from: makeImageData(width: 100, height: 80))
        let thumb = UIImage(data: thumbData)!
        XCTAssertEqual(thumb.size.width, 100)
        XCTAssertEqual(thumb.size.height, 80)
    }

    /// EXIF orientation=6(.right,90° 旋转):width/height 应互换,orientation 正确映射
    func testMetadataExifRotatedImage() throws {
        // 构造 640×480 像素 + EXIF orientation 6 的 JPEG
        let base = UIGraphicsImageRenderer(
            size: CGSize(width: 640, height: 480),
            format: {
                let f = UIGraphicsImageRendererFormat()
                f.scale = 1
                return f
            }()
        ).image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(
            dest, base.cgImage!,
            [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let legacy = UIImage(data: data as Data)!
        print("LEGACY:", legacy.size, legacy.imageOrientation.rawValue)

        let metadata = ImageImportProcessor().extractMetadata(from: data as Data)
        // 显示尺寸 = 旋转后互换(与旧实现 UIImage(data:).size 语义一致)
        XCTAssertEqual(metadata["width"] as? Int, 480)
        XCTAssertEqual(metadata["height"] as? Int, 640)
        XCTAssertEqual(
            metadata["orientation"] as? Int, UIImage.Orientation.right.rawValue)
    }
}
