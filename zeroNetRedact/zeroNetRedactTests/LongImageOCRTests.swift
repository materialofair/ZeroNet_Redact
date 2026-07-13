//
//  LongImageOCRTests.swift
//  zeroNetRedactTests
//
//  验证超长图(> 8192px)分块 OCR:头/中/尾的敏感信息全部检出且坐标正确
//

import UIKit
import XCTest

@testable import zeroNetRedact

final class LongImageOCRTests: XCTestCase {

    /// 渲染 1170×20000 长图,敏感信息分布在头/中/尾
    private func makeLongImage() -> Data {
        let size = CGSize(width: 1170, height: 20000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 40, weight: .medium),
            .foregroundColor: UIColor.black,
        ]
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ("联系电话: 13812345678" as NSString).draw(
                at: CGPoint(x: 60, y: 500), withAttributes: attrs)
            ("Email: test@example.com" as NSString).draw(
                at: CGPoint(x: 60, y: 10000), withAttributes: attrs)
            ("身份证号: 110101199003074518" as NSString).draw(
                at: CGPoint(x: 60, y: 19500), withAttributes: attrs)
        }
        return image.pngData()!
    }

    func testTiledOCRDetectsAllRegionsInLongImage() async throws {
        let data = makeLongImage()
        let recognizer = ImageOCRRecognizer()
        let texts = try await recognizer.recognizeText(in: data, fileType: .image)
        XCTAssertFalse(texts.isEmpty, "长图 OCR 未识别到任何文本")

        let regions = recognizer.detectSensitiveInfo(in: texts)
        let types = Set(regions.map(\.type))
        XCTAssertTrue(types.contains(.phoneNumber), "未检出头部手机号")
        XCTAssertTrue(types.contains(.email), "未检出中部邮箱")
        XCTAssertTrue(types.contains(.idCard), "未检出尾部身份证号")

        // 坐标应已映射回整图归一化空间(Vision 原点在左下):
        // 头部(y≈500/20000)的归一化 y 应接近 1,尾部接近 0
        let phone = regions.first { $0.type == .phoneNumber }!
        let idCard = regions.first { $0.type == .idCard }!
        XCTAssertGreaterThan(phone.boundingBox.midY, 0.9)
        XCTAssertLessThan(idCard.boundingBox.midY, 0.1)
        // 归一化高度应极小(40px 文字 / 20000px 高)
        XCTAssertLessThan(phone.boundingBox.height, 0.01)
    }

    /// 短图不受影响:走原单请求路径,行为与既有 SensitiveDetectionTests 一致
    func testShortImageStillWorks() async throws {
        let size = CGSize(width: 800, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ("Email: test@example.com" as NSString).draw(
                at: CGPoint(x: 40, y: 150),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black,
                ])
        }
        let recognizer = ImageOCRRecognizer()
        let texts = try await recognizer.recognizeText(in: image.pngData()!, fileType: .image)
        let regions = recognizer.detectSensitiveInfo(in: texts)
        XCTAssertTrue(regions.contains { $0.type == .email })
    }
}
