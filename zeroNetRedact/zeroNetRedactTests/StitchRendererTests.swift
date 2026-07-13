//
//  StitchRendererTests.swift
//  zeroNetRedactTests
//

import UIKit
import XCTest

@testable import zeroNetRedact

/// 直接持有 UIImage 的测试 provider
private struct ArrayProvider: StitchImageProvider {
    let images: [UIImage]
    func loadCGImage(at index: Int) throws -> CGImage {
        guard let cg = images[index].cgImage else {
            throw StitchRenderError.imageLoadFailed(index: index)
        }
        return cg
    }
}

final class StitchRendererTests: XCTestCase {

    func testOutputSizeSimpleStack() {
        let plan = StitchPlan(items: [
            StitchItem(pixelSize: CGSize(width: 390, height: 844)),
            StitchItem(pixelSize: CGSize(width: 390, height: 844)),
        ])
        let (size, scale) = StitchRenderer.outputSize(for: plan)
        XCTAssertEqual(scale, 1.0)
        XCTAssertEqual(size, CGSize(width: 390, height: 1688))
    }

    func testOutputSizeAppliesCrops() {
        var a = StitchItem(pixelSize: CGSize(width: 390, height: 844))
        a.cropBottom = 80
        var b = StitchItem(pixelSize: CGSize(width: 390, height: 844))
        b.cropTop = 264
        let (size, _) = StitchRenderer.outputSize(for: StitchPlan(items: [a, b]))
        XCTAssertEqual(size.height, 844 - 80 + 844 - 264)
    }

    func testOutputSizeCappedAt30MPixels() {
        // 2 × (1170×20000) = 46.8M 像素,超 3000 万上限 → 等比缩放
        let plan = StitchPlan(items: [
            StitchItem(pixelSize: CGSize(width: 1170, height: 20000)),
            StitchItem(pixelSize: CGSize(width: 1170, height: 20000)),
        ])
        let (size, scale) = StitchRenderer.outputSize(for: plan)
        XCTAssertLessThan(scale, 1.0)
        XCTAssertLessThanOrEqual(size.width * size.height, StitchRenderer.maxOutputPixels)
        XCTAssertGreaterThan(
            size.width * size.height, StitchRenderer.maxOutputPixels * 0.98,
            "应贴近上限而不是过度缩小")
    }

    /// 端到端:两张已知内容的图拼接后,接缝两侧像素应与源图一致
    func testRenderSeamPixelsMatchSources() throws {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let a = StitchTestImages.screenshot(from: world, contentTop: 0, contentHeight: 704)
        let b = StitchTestImages.screenshot(from: world, contentTop: 500, contentHeight: 704)

        var itemA = StitchItem(pixelSize: a.size)
        itemA.cropBottom = 80  // 裁页脚
        var itemB = StitchItem(pixelSize: b.size)
        itemB.cropTop = 60 + 204  // 裁页眉 + 重叠

        let data = try StitchRenderer.render(
            plan: StitchPlan(items: [itemA, itemB]),
            provider: ArrayProvider(images: [a, b]))
        let output = UIImage(data: data)!.cgImage!

        // 总高 = (844-80) + (844-264) = 1344
        XCTAssertEqual(output.height, 1344)
        XCTAssertEqual(output.width, 390)

        // 接缝上方 20px:应等于 world 中 y = 704-20-8=676 附近条纹
        // (A 的内容区底部,world y = 704 - 84 = ...)直接与源图 a 同位置比较
        let seamY = 844 - 80  // 输出中 A 段结束的位置
        let aGray = StitchTestImages.pixelGray(in: a.cgImage!, x: 195, y: seamY - 20)
        let outAGray = StitchTestImages.pixelGray(in: output, x: 195, y: seamY - 20)
        XCTAssertEqual(Double(outAGray), Double(aGray), accuracy: 0.06, "接缝上方来自 A")

        // 接缝下方 20px:应等于源图 b 中 cropTop+20 的像素
        let bGray = StitchTestImages.pixelGray(in: b.cgImage!, x: 195, y: 264 + 20)
        let outBGray = StitchTestImages.pixelGray(in: output, x: 195, y: seamY + 20)
        XCTAssertEqual(Double(outBGray), Double(bGray), accuracy: 0.06, "接缝下方来自 B")
    }

    func testRenderEmptyPlanThrows() {
        XCTAssertThrowsError(
            try StitchRenderer.render(
                plan: StitchPlan(items: []), provider: ArrayProvider(images: [])))
    }
}
