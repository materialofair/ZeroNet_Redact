import PDFKit
import XCTest
@testable import zeroNetRedact

final class TextSearchTests: XCTestCase {
    func testEveryOccurrenceUsesUTF16RangeAndKeepsPages() {
        var ranges: [NSRange] = []
        let texts = [0, 2].map { page in
            RecognizedText(text: "🙂王明 王明", boundingBox: .zero, confidence: 1,
                           pageIndex: page, substringBox: { range in
                ranges.append(range)
                return CGRect(x: range.location, y: 10, width: range.length, height: 10)
            })
        }
        let results = TextRecognizer.shared.findOccurrences(of: " 王明 ", in: texts)
        XCTAssertEqual(results.map(\.pageIndex), [0, 0, 2, 2])
        XCTAssertEqual(ranges, [NSRange(location: 2, length: 2), NSRange(location: 5, length: 2),
                                NSRange(location: 2, length: 2), NSRange(location: 5, length: 2)])
    }

    func testLiteralCaseSensitiveAndBlankSearch() {
        let texts = [RecognizedText(text: "ACME acme a.b", boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1), confidence: 1)]
        XCTAssertEqual(TextRecognizer.shared.findOccurrences(of: "acme", in: texts).count, 2)
        XCTAssertEqual(TextRecognizer.shared.findOccurrences(of: "acme", in: texts, options: .init(caseSensitive: true)).count, 1)
        XCTAssertEqual(TextRecognizer.shared.findOccurrences(of: "a.b", in: texts).count, 1)
        XCTAssertTrue(TextRecognizer.shared.findOccurrences(of: " \n", in: texts).isEmpty)
        XCTAssertTrue(TextRecognizer.shared.findOccurrences(of: "missing", in: texts).isEmpty)
    }

    func testPDFFullPhraseAcrossWordsAndPages() throws {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 400)).pdfData { context in
            for _ in 0..<2 {
                context.beginPage()
                ("Acme Company and Acme Company" as NSString).draw(at: CGPoint(x: 20, y: 60),
                     withAttributes: [.font: UIFont.systemFont(ofSize: 15)])
            }
        }
        let doc = try XCTUnwrap(PDFDocument(data: data))
        let results = TextRecognizer.shared.findOccurrences(of: "Acme Company", in: doc)
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(Set(results.compactMap(\.pageIndex)), [0, 1])
        XCTAssertTrue(results.allSatisfy { $0.boundingBox.width > 0 })
    }
}
