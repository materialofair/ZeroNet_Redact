//
//  RedactionRenderScaleTests.swift
//  zeroNetRedactTests
//
//  验证脱敏渲染不放大位图:
//  UIGraphicsImageRenderer默认format的scale是屏幕倍率(3x),
//  会把相机照片渲染成9倍像素量,导出PNG时内存暴涨导致OOM闪退
//

import CoreData
import UIKit
import XCTest

@testable import zeroNetRedact

final class RedactionRenderScaleTests: XCTestCase {

    private var editor: ImageRedactionEditor!

    override func setUp() {
        super.setUp()
        let context = PersistenceController.shared.container.viewContext
        let file = OriginalImage.create(
            in: context,
            id: UUID(),
            encryptedDataPath: "",
            encryptedThumbnailPath: "",
            fileSize: 0,
            width: 300,
            height: 400,
            orientation: .up,
            contentHash: "render-scale-test"
        )
        editor = ImageRedactionEditor(file: file)
    }

    override func tearDown() {
        PersistenceController.shared.container.viewContext.rollback()
        editor = nil
        super.tearDown()
    }

    private func makeImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// 矩形遮盖后像素尺寸应与原图一致(修复前会按屏幕倍率放大成3x)
    func testRectangleRedactionPreservesPixelDimensions() throws {
        editor.currentImage = makeImage(width: 300, height: 400)

        editor.applyRedaction(
            at: CGRect(x: 10, y: 10, width: 50, height: 50), effect: .solidBlack)

        let output = try XCTUnwrap(editor.currentImage?.cgImage)
        XCTAssertEqual(output.width, 300, "涂抹后位图宽度不应变化")
        XCTAssertEqual(output.height, 400, "涂抹后位图高度不应变化")
    }

    /// 马赛克(走compositeImage合成路径)同样不应放大位图
    func testMosaicRedactionPreservesPixelDimensions() throws {
        editor.currentImage = makeImage(width: 300, height: 400)

        editor.applyRedaction(
            at: CGRect(x: 10, y: 10, width: 50, height: 50), effect: .mosaic(pixelSize: 10))

        let output = try XCTUnwrap(editor.currentImage?.cgImage)
        XCTAssertEqual(output.width, 300, "马赛克后位图宽度不应变化")
        XCTAssertEqual(output.height, 400, "马赛克后位图高度不应变化")
    }

    /// 连续多次涂抹也不应逐次放大
    func testRepeatedRedactionsDoNotInflatePixels() throws {
        editor.currentImage = makeImage(width: 300, height: 400)

        for i in 0..<3 {
            editor.applyRedaction(
                at: CGRect(x: 10 + i * 20, y: 10, width: 30, height: 30), effect: .solidBlack)
        }

        let output = try XCTUnwrap(editor.currentImage?.cgImage)
        XCTAssertEqual(output.width, 300)
        XCTAssertEqual(output.height, 400)
    }
}
