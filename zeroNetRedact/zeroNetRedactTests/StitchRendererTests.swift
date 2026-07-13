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

    /// 回归:触发 30MP 压缩路径时,累计绘制高度必须铺满画布(底部不得留白条)
    func testRenderCappedPathFillsCanvasBottom() throws {
        // 两张 1170×20000 纯色图(灰度不同),总像素 46.8M 触发压缩
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 1170, height: 20000)
        let images: [UIImage] = [0.2, 0.7].map { gray in
            UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                ctx.cgContext.setFillColor(CGColor(gray: gray, alpha: 1))
                ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            }
        }
        let plan = StitchPlan(items: [
            StitchItem(pixelSize: size), StitchItem(pixelSize: size),
        ])
        let data = try StitchRenderer.render(
            plan: plan, provider: ArrayProvider(images: images))
        let output = UIImage(data: data)!.cgImage!

        // 底部一行应是第二张图的灰度(0.7),而不是白底(1.0)
        let bottomGray = StitchTestImages.pixelGray(
            in: output, x: output.width / 2, y: output.height - 1)
        XCTAssertEqual(Double(bottomGray), 0.7, accuracy: 0.08, "画布底部留白 → 压缩路径取整误差回归")
        // 顶部一行应是第一张图的灰度
        let topGray = StitchTestImages.pixelGray(in: output, x: output.width / 2, y: 0)
        XCTAssertEqual(Double(topGray), 0.2, accuracy: 0.08)
    }

    /// 回归:分数像素裁剪值(降采样映射的常态)不得在拼缝处残留白底横线。
    /// 机制:分数边界光栅化时上段与白底混合、下段再叠加,接缝行残留 ~20% 白底成分。
    func testRenderFractionalSeamHasNoWhiteLine() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 390, height: 844)
        // 深色对(0.1/0.15):白底渗漏会显著抬高接缝行灰度;
        // 两色差刻意很小,使 JPEG 阶跃振铃(∝ 边缘幅度)不会误触阈值
        let images: [UIImage] = [0.1, 0.15].map { gray in
            UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                ctx.cgContext.setFillColor(CGColor(gray: gray, alpha: 1))
                ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            }
        }
        // 模拟指纹行→原图像素映射产生的分数裁剪值
        var itemA = StitchItem(pixelSize: size)
        itemA.cropBottom = 80.4
        var itemB = StitchItem(pixelSize: size)
        itemB.cropTop = 264.6
        let data = try StitchRenderer.render(
            plan: StitchPlan(items: [itemA, itemB]),
            provider: ArrayProvider(images: images))
        let output = UIImage(data: data)!.cgImage!

        // 全图逐行采样:任何一行都不得明显亮于两种源色(白底渗漏 = 拼缝横线)
        var maxGray: Double = 0
        var maxRow = -1
        for row in 0..<output.height {
            let gray = Double(
                StitchTestImages.pixelGray(in: output, x: output.width / 2, y: row))
            if gray > maxGray {
                maxGray = gray
                maxRow = row
            }
        }
        XCTAssertLessThan(maxGray, 0.25, "第 \(maxRow) 行出现白底渗漏横线(灰度 \(maxGray))")
    }
}
