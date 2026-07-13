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
}
