//
//  PageIndexDedupTests.swift
//  验证 OCR 检测区域去重按 (pageIndex, bounds) 分组：
//  不同页相同坐标的检测结果不得被误删（P1-13 正确性问题）
//

import XCTest

@testable import zeroNetRedact

final class PageIndexDedupTests: XCTestCase {

    private func makeRegion(
        pageIndex: Int?, bounds: CGRect, type: SensitiveType = .phoneNumber
    ) -> SensitiveRegion {
        SensitiveRegion(
            type: type,
            boundingBox: bounds,
            confidence: 1.0,
            pageIndex: pageIndex,
            isConfirmed: false,
            recognizedText: "13812345678"
        )
    }

    /// 同页重叠区域应去重（保持原有行为）
    func testSamePageOverlapDeduplicated() {
        let recognizer = TextRecognizer.shared
        let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)

        let texts = [
            RecognizedText(text: "13812345678", boundingBox: box, confidence: 1.0, pageIndex: 0),
            RecognizedText(
                text: "13812345678",
                boundingBox: box.insetBy(dx: -0.01, dy: -0.01),
                confidence: 1.0,
                pageIndex: 0
            ),
        ]

        let regions = recognizer.detectSensitiveRegions(in: texts)
        XCTAssertEqual(regions.count, 1, "同页重叠区域应去重为 1 个")
    }

    /// 不同页相同坐标的检测结果必须全部保留（修复前会被误删）
    func testSameBoundsOnDifferentPagesAllKept() {
        let recognizer = TextRecognizer.shared
        let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)

        let texts = [
            RecognizedText(text: "13812345678", boundingBox: box, confidence: 1.0, pageIndex: 0),
            RecognizedText(text: "13812345678", boundingBox: box, confidence: 1.0, pageIndex: 1),
            RecognizedText(text: "13812345678", boundingBox: box, confidence: 1.0, pageIndex: 2),
        ]

        let regions = recognizer.detectSensitiveRegions(in: texts)
        XCTAssertEqual(regions.count, 3, "不同页相同坐标的检测结果应全部保留")
        XCTAssertEqual(Set(regions.compactMap(\.pageIndex)), [0, 1, 2])
    }

    /// 无页码的图片文件（pageIndex 为 nil）之间仍按重叠去重
    func testNilPageIndexStillDeduplicatedByOverlap() {
        let recognizer = TextRecognizer.shared
        let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)

        let texts = [
            RecognizedText(text: "13812345678", boundingBox: box, confidence: 1.0),
            RecognizedText(
                text: "13812345678",
                boundingBox: box.insetBy(dx: -0.01, dy: -0.01),
                confidence: 1.0
            ),
        ]

        let regions = recognizer.detectSensitiveRegions(in: texts)
        XCTAssertEqual(regions.count, 1, "无页码的重叠区域仍应去重")
    }

    /// nil 页码与有页码的区域互不干扰
    func testNilPageDoesNotConflictWithNumberedPages() {
        let recognizer = TextRecognizer.shared
        let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)

        let texts = [
            RecognizedText(text: "13812345678", boundingBox: box, confidence: 1.0),
            RecognizedText(text: "13812345678", boundingBox: box, confidence: 1.0, pageIndex: 0),
        ]

        let regions = recognizer.detectSensitiveRegions(in: texts)
        XCTAssertEqual(regions.count, 2, "nil 页码与有页码的区域应互不干扰")
    }
}
