//
//  MuPDFRedactorTests.swift
//  ZeroNet Redact
//
//  PDF 真删除（MuPDF）单元测试
//

import PDFKit
import UIKit
import XCTest

@testable import zeroNetRedact

final class MuPDFRedactorTests: XCTestCase {

    // MARK: - 文本 PDF fixture

    private func makeTextPDF(
        pages: [[(text: String, rect: CGRect)]],
        pageSize: CGSize = CGSize(width: 612, height: 792)
    ) throws -> Data {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { ctx in
            for page in pages {
                ctx.beginPage()
                for line in page {
                    line.text.draw(
                        in: line.rect,
                        withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
                }
            }
        }
    }

    // MARK: - /Rotate 90 fixture（手工构造最小 PDF）

    private func makeRotatedPDFData() -> Data {
        let stream = "BT /F1 14 Tf 30 250 Td (ROTATED-SECRET) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Rotate 90 "
                + "/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ]

        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xrefPosition = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n"
        pdf += "0000000000 65535 f \n"
        for offset in offsets {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\n"
        pdf += "startxref\n\(xrefPosition)\n%%EOF\n"
        return Data(pdf.utf8)
    }

    // MARK: - 测试

    /// 辅助：用 PDFKit 定位文字（与 App 检测路径同空间），返回红色区域矩形
    private func redactionRect(
        in document: PDFDocument, pageIndex: Int, text needle: String
    ) throws -> CGRect {
        let selection = try XCTUnwrap(
            document.findString(needle, withOptions: []).first)
        let page = try XCTUnwrap(document.page(at: pageIndex))
        return selection.bounds(for: page).insetBy(dx: -5, dy: -5)
    }

    /// 遮盖区域内的文字被物理删除，其他文字保留，输出无残留注释
    func testRedactRemovesCoveredTextAndKeepsTheRest() throws {
        let input = try makeTextPDF(pages: [[
            ("SENSITIVE-13812345678", CGRect(x: 60, y: 60, width: 400, height: 30)),
            ("PUBLIC-KEEP", CGRect(x: 60, y: 120, width: 400, height: 30)),
        ]])

        let sourceDocument = try XCTUnwrap(PDFDocument(data: input))
        let rect = try redactionRect(
            in: sourceDocument, pageIndex: 0, text: "SENSITIVE")

        let output = try MuPDFRedactor.redact(
            pdfData: input,
            regions: [PDFRedactionRegion(pageIndex: 0, rect: rect)])

        let document = try XCTUnwrap(PDFDocument(data: output))
        let page = try XCTUnwrap(document.page(at: 0))
        let text = page.string ?? ""
        XCTAssertFalse(text.contains("SENSITIVE"), "遮盖区域文字应被删除，实际: \(text)")
        XCTAssertTrue(text.contains("PUBLIC-KEEP"), "非遮盖文字应保留，实际: \(text)")
        XCTAssertTrue(page.annotations.isEmpty, "真删除后输出不应残留注释")
    }

    /// 区域只作用于指定页
    func testRedactOnlyTargetsTheGivenPage() throws {
        let input = try makeTextPDF(pages: [
            [("SENSITIVE-13812345678", CGRect(x: 60, y: 60, width: 400, height: 30))],
            [("PAGE2-KEEP", CGRect(x: 60, y: 60, width: 400, height: 30))],
        ])

        let sourceDocument = try XCTUnwrap(PDFDocument(data: input))
        let rect = try redactionRect(
            in: sourceDocument, pageIndex: 0, text: "SENSITIVE")

        let output = try MuPDFRedactor.redact(
            pdfData: input,
            regions: [PDFRedactionRegion(pageIndex: 0, rect: rect)])

        let document = try XCTUnwrap(PDFDocument(data: output))
        let page0Text = document.page(at: 0)?.string ?? ""
        XCTAssertFalse(page0Text.contains("SENSITIVE"), "遮盖文字应被删除，实际: \(page0Text)")
        let page1Text = try XCTUnwrap(document.page(at: 1)?.string)
        XCTAssertTrue(page1Text.contains("PAGE2-KEEP"), "其他页文字应保留，实际: \(page1Text)")
    }

    /// 旋转页：使用 App 真实数据路径的坐标（检测结果的 selection.bounds，与 annotation.bounds 同空间）做真删除
    func testRedactOnRotatedPageUsingPDFKitCoordinates() throws {
        let input = makeRotatedPDFData()

        let sourceDocument = try XCTUnwrap(PDFDocument(data: input))
        let selection = try XCTUnwrap(
            sourceDocument.findString("ROTATED-SECRET", withOptions: []).first)
        let sourcePage = try XCTUnwrap(sourceDocument.page(at: 0))
        var rect = selection.bounds(for: sourcePage)
        rect = rect.insetBy(dx: -5, dy: -5)

        let output = try MuPDFRedactor.redact(
            pdfData: input,
            regions: [PDFRedactionRegion(pageIndex: 0, rect: rect)])

        let document = try XCTUnwrap(PDFDocument(data: output))
        let text = document.page(at: 0)?.string ?? ""
        XCTAssertFalse(text.contains("ROTATED-SECRET"), "旋转页上的遮盖文字应被删除，实际: \(text)")
    }

    /// 零区域：原样往返，文字完好
    func testZeroRegionsReturnsIntactPDF() throws {
        let input = try makeTextPDF(pages: [[
            ("KEEP-ME", CGRect(x: 60, y: 60, width: 200, height: 30)),
        ]])

        let output = try MuPDFRedactor.redact(pdfData: input, regions: [])

        let document = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertTrue(
            try XCTUnwrap(document.page(at: 0)?.string).contains("KEEP-ME"))
    }

    /// 损坏输入：抛错而非崩溃
    func testCorruptInputThrows() {
        let garbage = Data("this is not a pdf".utf8)
        XCTAssertThrowsError(
            try MuPDFRedactor.redact(
                pdfData: garbage,
                regions: [PDFRedactionRegion(
                    pageIndex: 0, rect: CGRect(x: 0, y: 0, width: 100, height: 100))]))
    }

    /// 越界页码：抛错而非崩溃
    func testOutOfRangePageIndexThrows() throws {
        let input = try makeTextPDF(pages: [[
            ("KEEP-ME", CGRect(x: 60, y: 60, width: 200, height: 30)),
        ]])
        XCTAssertThrowsError(
            try MuPDFRedactor.redact(
                pdfData: input,
                regions: [PDFRedactionRegion(
                    pageIndex: 99, rect: CGRect(x: 0, y: 0, width: 100, height: 100))]))
    }
}
