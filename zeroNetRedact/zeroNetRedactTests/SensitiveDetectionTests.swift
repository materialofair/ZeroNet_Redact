//
//  SensitiveDetectionTests.swift
//  验证"AI 自动识别敏感信息"管线端到端可用（Vision OCR + 正则匹配）
//

import UIKit
import XCTest

@testable import zeroNetRedact

final class SensitiveDetectionTests: XCTestCase {

    /// 生成一张包含敏感信息文本的图片，跑完整识别管线，验证能检出手机号/邮箱/身份证
    func testDetectSensitiveInfoInRenderedImage() async throws {
        let lines = [
            "联系电话: 13812345678",
            "Email: test@example.com",
            "身份证号: 110101199003074518",
        ]
        let size = CGSize(width: 800, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .medium),
                .foregroundColor: UIColor.black,
            ]
            for (i, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: CGPoint(x: 40, y: 60 + CGFloat(i) * 100), withAttributes: attrs)
            }
        }
        let data = try XCTUnwrap(image.pngData())

        // 1. Vision OCR
        let recognizer = ImageOCRRecognizer()
        let texts = try await recognizer.recognizeText(in: data, fileType: .image)
        print("DETECT-REPRO: OCR 识别到 \(texts.count) 段文本: \(texts.map(\.text))")
        XCTAssertFalse(texts.isEmpty, "OCR 未识别到任何文本")

        // 2. 敏感信息匹配
        let regions = recognizer.detectSensitiveInfo(in: texts)
        let types = Set(regions.map(\.type))
        print("DETECT-REPRO: 检出 \(regions.count) 处敏感信息, 类型: \(types)")

        XCTAssertTrue(types.contains(.phoneNumber), "未检出手机号")
        XCTAssertTrue(types.contains(.email), "未检出邮箱")
        XCTAssertTrue(types.contains(.idCard), "未检出身份证号")

        // 3. 检出区域应有有效的归一化坐标（供画布高亮/打码使用）
        for region in regions {
            XCTAssertFalse(region.boundingBox.isEmpty, "检出区域坐标为空: \(region.type)")
        }
    }
}
