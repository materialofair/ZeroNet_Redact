//
//  StitchEngineTests.swift
//  zeroNetRedactTests
//

import UIKit
import XCTest

@testable import zeroNetRedact

final class StitchEngineTests: XCTestCase {

    private func makeShotData(contentTop: CGFloat, world: UIImage) -> Data {
        StitchTestImages.screenshot(from: world, contentTop: contentTop, contentHeight: 704)
            .pngData()!
    }

    func testMakeSourceExtractsSizePreviewAndFingerprints() throws {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let source = try StitchEngine.makeSource(from: makeShotData(contentTop: 0, world: world))

        XCTAssertEqual(source.pixelSize, CGSize(width: 390, height: 844))
        XCTAssertLessThanOrEqual(source.preview.size.width, 750)
        XCTAssertFalse(source.fingerprints.isEmpty)
        XCTAssertEqual(source.fingerprints.count, Int(source.preview.size.height))
    }

    func testMakeSourceRejectsGarbage() {
        XCTAssertThrowsError(try StitchEngine.makeSource(from: Data([0x00, 0x01, 0x02])))
    }

    /// 端到端:两张 PNG 数据 → 方案 → 渲染,输出高度符合"页脚+页眉+重叠都被裁掉"
    func testEndToEndStitchTwoScreenshots() throws {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let sources = try [0.0, 500.0].map {
            try StitchEngine.makeSource(from: makeShotData(contentTop: $0, world: world))
        }
        let plan = StitchEngine.computePlan(for: sources)
        XCTAssertGreaterThanOrEqual(plan.items[1].seamConfidence, 0.92)

        let data = try StitchEngine.render(plan: plan, sources: sources)
        let output = UIImage(data: data)!
        // 期望高度 = (844-80) + (844-60-204) = 1344,容忍检测量化误差
        XCTAssertEqual(Double(output.size.height), 1344, accuracy: 25)
        XCTAssertEqual(output.size.width, 390)
    }
}
