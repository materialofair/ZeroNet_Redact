import PDFKit
import XCTest
@testable import zeroNetRedact

final class ExportProcessingReportTests: XCTestCase {
    func testInvalidOutputDoesNotClaimMetadataWasRemoved() {
        let report = ExportProcessingReport.inspect(data: Data(), isPDF: true, regionCount: 3)
        XCTAssertEqual(report.regionCount, 3)
        XCTAssertTrue(report.verifiedAbsentFields.isEmpty)
    }

    func testExistingAuthorIsNotReportedAbsent() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        document.documentAttributes = [PDFDocumentAttribute.authorAttribute: "Example"]
        let data = try XCTUnwrap(document.dataRepresentation())
        let report = ExportProcessingReport.inspect(data: data, isPDF: true, regionCount: 0)
        XCTAssertFalse(report.verifiedAbsentFields.contains("report.author"))
        XCTAssertEqual(report.size, data.count)
    }
}
