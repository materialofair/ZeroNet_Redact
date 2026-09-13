import XCTest
@testable import zeroNetRedact

final class PDFReviewNavigatorTests: XCTestCase {
    private func item(_ page: Int?) -> SensitiveRegion {
        SensitiveRegion(type: .custom, boundingBox: .zero, confidence: 1, pageIndex: page)
    }
    func testMovesWithinPageThenAcrossPagesAndWraps() {
        let a = item(0), b = item(0), c = item(4)
        let items = [c, a, b]
        XCTAssertEqual(PendingRegionNavigation.next(in: items, currentPage: 0, after: nil)?.id, a.id)
        XCTAssertEqual(PendingRegionNavigation.next(in: items, currentPage: 0, after: a.id)?.id, b.id)
        XCTAssertEqual(PendingRegionNavigation.next(in: items, currentPage: 0, after: b.id)?.id, c.id)
        XCTAssertEqual(PendingRegionNavigation.next(in: items, currentPage: 4, after: c.id)?.id, a.id)
    }
    func testProcessedItemAndUnknownPageRemainReachable() {
        let a = item(0), unknown = item(nil), c = item(4)
        XCTAssertEqual(PendingRegionNavigation.next(in: [unknown, c], currentPage: 0, after: a.id)?.id, c.id)
        XCTAssertEqual(PendingRegionNavigation.next(in: [unknown, c], currentPage: 4, after: c.id)?.id, unknown.id)
        XCTAssertNil(PendingRegionNavigation.next(in: [], currentPage: 0, after: nil))
    }
}
