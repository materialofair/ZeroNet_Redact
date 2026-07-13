//
//  OverlapDetectorTests.swift
//  zeroNetRedactTests
//

import XCTest

@testable import zeroNetRedact

final class OverlapDetectorTests: XCTestCase {

    // MARK: 行指纹

    func testRowFingerprintsShapeAndValues() {
        let world = StitchTestImages.world(width: 390, height: 400)
        let fps = OverlapDetector.rowFingerprints(of: world.cgImage!)

        XCTAssertEqual(fps.count, 400, "每个像素行一条指纹")
        XCTAssertEqual(fps[0].count, OverlapDetector.samplesPerRow)
        // 纯色横纹:同一行内所有采样值相同
        let first = fps[10][0]
        XCTAssertTrue(fps[10].allSatisfy { abs($0 - first) < 0.02 })
        // 同一条纹内的两行指纹一致,跨条纹的两行不一致
        XCTAssertGreaterThan(OverlapDetector.rowSimilarity(fps[0], fps[7]), 0.98)
        var foundDifferent = false
        for row in stride(from: 8, to: 400, by: 8)
        where OverlapDetector.rowSimilarity(fps[0], fps[row]) < 0.9 {
            foundDifferent = true
            break
        }
        XCTAssertTrue(foundDifferent, "不同条纹应产生不同指纹")
    }

    func testRowSimilarityTrimmedIgnoresLocalChange() {
        var a = [Float](repeating: 0.5, count: 32)
        var b = a
        // 模拟状态栏时钟:32 个采样点中 4 个突变
        for i in 27..<31 { b[i] = 1.0 }
        XCTAssertLessThan(OverlapDetector.rowSimilarity(a, b), 0.95, "普通相似度应被拉低")
        XCTAssertGreaterThan(
            OverlapDetector.rowSimilarity(a, b, trimRatio: 0.25), 0.99,
            "截尾相似度应忽略局部突变")
        a = []; b = []
        XCTAssertEqual(OverlapDetector.rowSimilarity(a, b), 0, "空指纹相似度为 0")
    }

    // MARK: 固定页眉/页脚检测

    /// 三张截图共享 60px 页眉、80px 页脚(页眉带"时钟变化"),内容各不相同
    func testDetectFixedRegionsWithClockTolerance() {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let shots = [0.0, 500.0, 1100.0].enumerated().map { i, top in
            StitchTestImages.screenshot(
                from: world, contentTop: top, contentHeight: 700,
                headerBadgeGray: 0.3 + CGFloat(i) * 0.2)  // 每张"时钟"都不同
        }
        let fps = shots.map { OverlapDetector.rowFingerprints(of: $0.cgImage!) }
        let fixed = OverlapDetector.detectFixedRegions(fps)

        XCTAssertEqual(Double(fixed.headerRows), 60, accuracy: 10, "页眉约 60 行(容忍条纹边界)")
        XCTAssertEqual(Double(fixed.footerRows), 80, accuracy: 10, "页脚约 80 行")
    }

    /// 无固定区的两张图(纯内容,页眉页脚高度为 0)
    func testDetectFixedRegionsNoneWhenContentDiffers() {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let a = StitchTestImages.screenshot(
            from: world, contentTop: 0, contentHeight: 700, headerHeight: 0, footerHeight: 0)
        let b = StitchTestImages.screenshot(
            from: world, contentTop: 900, contentHeight: 700, headerHeight: 0, footerHeight: 0)
        let fps = [a, b].map { OverlapDetector.rowFingerprints(of: $0.cgImage!) }
        let fixed = OverlapDetector.detectFixedRegions(fps)

        XCTAssertLessThan(fixed.headerRows, 16, "无共同页眉时应接近 0")
        XCTAssertLessThan(fixed.footerRows, 16)
    }

    /// 固定区上限:两张完全相同的图,固定区不得超过图高的 25%
    func testDetectFixedRegionsCapped() {
        let world = StitchTestImages.world(width: 390, height: 800)
        let fps = [world, world].map { OverlapDetector.rowFingerprints(of: $0.cgImage!) }
        let fixed = OverlapDetector.detectFixedRegions(fps)

        XCTAssertLessThanOrEqual(fixed.headerRows, 200)
        XCTAssertLessThanOrEqual(fixed.footerRows, 200)
    }
}
