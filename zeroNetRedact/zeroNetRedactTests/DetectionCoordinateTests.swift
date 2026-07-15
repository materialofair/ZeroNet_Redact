//
//  DetectionCoordinateTests.swift
//  zeroNetRedactTests
//
//  验证AI检测框位置正确性:
//  1. PDF: 检测框应落在敏感词实际位置,而非页面开头
//  2. 图片: 带EXIF方向的图片(相机照片)检测框应落在显示空间的正确位置
//

import PDFKit
import UIKit
import XCTest

@testable import zeroNetRedact

final class DetectionCoordinateTests: XCTestCase {

    // MARK: - PDF 检测框位置

    /// 生成单页PDF:页首为普通文本,手机号绘制在页面底部
    private func makePDFWithPhoneAtBottom() -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18),
            .foregroundColor: UIColor.black,
        ]
        return renderer.pdfData { ctx in
            ctx.beginPage()
            ("Ordinary header text here" as NSString).draw(
                at: CGPoint(x: 50, y: 50), withAttributes: attrs)
            ("Phone: 13812345678" as NSString).draw(
                at: CGPoint(x: 50, y: 700), withAttributes: attrs)
        }
    }

    func testPDFRegionBoundingBoxMatchesTextPosition() async throws {
        let data = makePDFWithPhoneAtBottom()
        let recognizer = PDFTextRecognizer()
        let texts = try await recognizer.recognizeText(in: data, fileType: .pdf)
        XCTAssertFalse(texts.isEmpty, "PDF 未提取到任何文本")

        let regions = recognizer.detectSensitiveInfo(in: texts)
        let phone = regions.first { $0.type == .phoneNumber }
        XCTAssertNotNil(phone, "未检出手机号")

        // PDF页面坐标左下角为原点:手机号绘制在UIKit y=700(页面底部),
        // 对应PDF y ≈ 792 - 700 - 字高 ≈ 74,检测框应在页面下半部
        // (Bug表现: selection永远取页首前N个字符,框落在 y ≈ 730 附近)
        guard let box = phone?.boundingBox else { return }
        XCTAssertLessThan(box.midY, 200, "检测框应在页面底部附近,实际: \(box)")
        XCTAssertGreaterThan(box.minX, 40, "检测框x应在文本绘制位置附近,实际: \(box)")
    }

    /// 同一敏感词出现两次时,第二次出现的位置也应正确(顺序推进搜索)
    func testPDFDuplicateWordsGetDistinctPositions() async throws {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18),
            .foregroundColor: UIColor.black,
        ]
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            ("13812345678" as NSString).draw(at: CGPoint(x: 50, y: 100), withAttributes: attrs)
            ("13812345678" as NSString).draw(at: CGPoint(x: 50, y: 600), withAttributes: attrs)
        }

        let recognizer = PDFTextRecognizer()
        let texts = try await recognizer.recognizeText(in: data, fileType: .pdf)
        let phoneTexts = texts.filter { $0.text == "13812345678" }
        XCTAssertEqual(phoneTexts.count, 2, "应提取到两个手机号文本")

        let ys = Set(phoneTexts.map { Int($0.boundingBox.midY) })
        XCTAssertEqual(ys.count, 2, "两次出现应有不同的y坐标,实际: \(phoneTexts.map(\.boundingBox))")
    }

    // MARK: - 图片 EXIF 方向

    /// 渲染竖幅图片(600×1200),手机号位于顶部
    private func makeUprightImage() -> UIImage {
        let size = CGSize(width: 600, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ("Phone: 13812345678" as NSString).draw(
                at: CGPoint(x: 40, y: 100),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 36, weight: .medium),
                    .foregroundColor: UIColor.black,
                ])
        }
    }

    /// 模拟相机竖拍照片:原始位图为逆时针旋转90°的横置内容 + orientation=.right
    private func makeCameraStyleImage(from upright: UIImage) -> UIImage {
        let rawSize = CGSize(width: upright.size.height, height: upright.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let raw = UIGraphicsImageRenderer(size: rawSize, format: format).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: rawSize.width / 2, y: rawSize.height / 2)
            c.rotate(by: -.pi / 2)
            upright.draw(
                in: CGRect(
                    x: -upright.size.width / 2, y: -upright.size.height / 2,
                    width: upright.size.width, height: upright.size.height))
        }
        return UIImage(cgImage: raw.cgImage!, scale: 1, orientation: .right)
    }

    // MARK: - 内容旋转(横放证件)

    /// 模拟横放拍摄的证件:位图本身顺时针旋转90°,无EXIF方向信息
    /// 正向OCR对90°文字几何不可靠,应通过多方向识别修正
    func testOCRHandlesContentRotatedImage() async throws {
        let upright = makeUprightImage()
        let rawSize = CGSize(width: upright.size.height, height: upright.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let raw = UIGraphicsImageRenderer(size: rawSize, format: format).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: rawSize.width / 2, y: rawSize.height / 2)
            c.rotate(by: .pi / 2)
            upright.draw(
                in: CGRect(
                    x: -upright.size.width / 2, y: -upright.size.height / 2,
                    width: upright.size.width, height: upright.size.height))
        }

        let recognizer = ImageOCRRecognizer()
        let texts = try await recognizer.recognizeText(in: raw.pngData()!, fileType: .image)
        let regions = recognizer.detectSensitiveInfo(in: texts)
        let phone = regions.first { $0.type == .phoneNumber }
        XCTAssertNotNil(phone, "内容旋转90°的图片未检出手机号")

        // 竖幅内容顺时针旋转后:手机号(原顶部,x=40..390,y=100..136)
        // 在原始位图归一化空间(左下原点)应为 x≈0.887..0.917, y≈0.35..0.93 的竖条
        guard let box = phone?.boundingBox else { return }
        XCTAssertGreaterThan(box.midX, 0.85, "检测框应贴近右缘,实际: \(box)")
        XCTAssertLessThan(box.width, 0.1, "检测框应为窄竖条,实际: \(box)")
        XCTAssertGreaterThan(box.height, 0.35, "检测框应覆盖号码全长,实际: \(box)")
        XCTAssertLessThan(abs(box.midY - 0.64), 0.15, "检测框中心应对准号码,实际: \(box)")
    }

    // MARK: - 子串级精确框

    /// 敏感号码只占识别行的一部分时,检测框应贴合号码本身而非整行
    func testRegionBoxCoversOnlyMatchedSubstring() async throws {
        let size = CGSize(width: 1000, height: 400)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 36, weight: .medium),
            .foregroundColor: UIColor.black,
        ]
        let prefix = "客服电话: "
        let number = "13812345678"
        let suffix = " 转 8001 谢谢配合"
        let line = prefix + number + suffix
        let originX: CGFloat = 40
        let prefixWidth = (prefix as NSString).size(withAttributes: attrs).width
        let numberWidth = (number as NSString).size(withAttributes: attrs).width

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            (line as NSString).draw(at: CGPoint(x: originX, y: 180), withAttributes: attrs)
        }

        let recognizer = ImageOCRRecognizer()
        let texts = try await recognizer.recognizeText(in: image.pngData()!, fileType: .image)
        let regions = recognizer.detectSensitiveInfo(in: texts)
        let phone = regions.first { $0.type == .phoneNumber }
        XCTAssertNotNil(phone, "未检出手机号")

        // 期望框只覆盖号码段: x ≈ (40+prefixWidth)/1000 .. (40+prefixWidth+numberWidth)/1000
        let expectedMidX = (originX + prefixWidth + numberWidth / 2) / size.width
        let expectedWidth = numberWidth / size.width
        guard let box = phone?.boundingBox else { return }
        XCTAssertLessThan(
            box.width, expectedWidth + 0.08,
            "检测框宽度应贴合号码段而非整行,实际: \(box), 号码段宽度: \(expectedWidth)")
        XCTAssertLessThan(
            abs(box.midX - expectedMidX), 0.08,
            "检测框中心应对准号码段,实际: \(box), 期望midX: \(expectedMidX)")
    }

    /// 号码带空格分隔(清理后才匹配)时,框也应贴合号码段(验证清理文本索引回映射)
    func testRegionBoxForSpacedNumberViaCleanedText() async throws {
        let size = CGSize(width: 1000, height: 400)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 34, weight: .medium),
            .foregroundColor: UIColor.black,
        ]
        let prefix = "卡号 "
        let number = "6222 0212 3456 7890"
        let suffix = " 已绑定"
        let originX: CGFloat = 40
        let prefixWidth = (prefix as NSString).size(withAttributes: attrs).width
        let numberWidth = (number as NSString).size(withAttributes: attrs).width

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ((prefix + number + suffix) as NSString).draw(
                at: CGPoint(x: originX, y: 180), withAttributes: attrs)
        }

        let recognizer = ImageOCRRecognizer()
        let texts = try await recognizer.recognizeText(in: image.pngData()!, fileType: .image)
        let regions = recognizer.detectSensitiveInfo(in: texts)
        let card = regions.first { $0.type == .bankCard }
        XCTAssertNotNil(card, "未检出银行卡号")

        let expectedMidX = (originX + prefixWidth + numberWidth / 2) / size.width
        let expectedWidth = numberWidth / size.width
        guard let box = card?.boundingBox else { return }
        XCTAssertLessThan(
            box.width, expectedWidth + 0.08,
            "检测框宽度应贴合卡号段,实际: \(box), 卡号段宽度: \(expectedWidth)")
        XCTAssertLessThan(
            abs(box.midX - expectedMidX), 0.08,
            "检测框中心应对准卡号段,实际: \(box), 期望midX: \(expectedMidX)")
    }

    func testOCRHandlesEXIFOrientedImage() async throws {
        let camera = makeCameraStyleImage(from: makeUprightImage())
        // 显示尺寸应仍为竖幅(与相册中带EXIF方向的照片一致)
        XCTAssertEqual(camera.size, CGSize(width: 600, height: 1200))

        // jpegData 保留EXIF方向,与导入管线存储的原始字节一致
        let jpegData = try XCTUnwrap(camera.jpegData(compressionQuality: 0.9))

        let recognizer = ImageOCRRecognizer()
        let texts = try await recognizer.recognizeText(in: jpegData, fileType: .image)
        let regions = recognizer.detectSensitiveInfo(in: texts)
        let phone = regions.first { $0.type == .phoneNumber }
        XCTAssertNotNil(phone, "带EXIF方向的图片未检出手机号")

        // 手机号在显示空间的顶部 → Vision归一化坐标(左下原点) midY 应接近1
        guard let box = phone?.boundingBox else { return }
        XCTAssertGreaterThan(box.midY, 0.8, "检测框应在图片顶部,实际: \(box)")
    }
}
