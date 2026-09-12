import XCTest

@testable import zeroNetRedact

final class DetectionReviewTests: XCTestCase {
    private func region(page: Int?) -> SensitiveRegion {
        SensitiveRegion(
            type: .phoneNumber,
            boundingBox: CGRect(x: 10, y: 10, width: 100, height: 20),
            confidence: 1,
            pageIndex: page
        )
    }

    func testReviewIncludesOtherPagesInDocumentOrder() {
        let last = region(page: 9)
        let first = region(page: 0)
        let anotherOnLast = region(page: 9)
        let pages = DetectionReviewPage.grouped([last, first, anotherOnLast], isPDF: true)

        XCTAssertEqual(pages.map(\.pageIndex), [0, 9])
        XCTAssertEqual(pages.map { $0.regions.count }, [1, 2])
        XCTAssertEqual(pages[1].regions.map(\.id), [last.id, anotherOnLast.id])
    }

    func testProcessingCurrentPageLeavesOtherPageReviewable() {
        let first = region(page: 0)
        let second = region(page: 1)
        var pending = [first, second]
        pending.removeAll { $0.pageIndex == 0 }
        let pages = DetectionReviewPage.grouped(pending, isPDF: true)

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].pageIndex, 1)
        XCTAssertEqual(pages[0].regions.first?.id, second.id)
    }

    func testUnknownPDFPageIsNotSilentlyDropped() {
        let unknown = region(page: nil)
        let known = region(page: 2)
        let pages = DetectionReviewPage.grouped([known, unknown], isPDF: true)

        XCTAssertEqual(pages.flatMap(\.regions).count, 2)
        XCTAssertEqual(pages.first?.regions.first?.id, unknown.id)
        XCTAssertEqual(Set(pages.map(\.id)).count, 2)
    }

    func testImageReviewPreservesAllCandidatesWithoutPageSections() {
        let regions = [region(page: nil), region(page: nil)]
        let pages = DetectionReviewPage.grouped(regions, isPDF: false)

        XCTAssertEqual(pages.count, 1)
        XCTAssertNil(pages[0].pageIndex)
        XCTAssertEqual(pages[0].regions.map(\.id), regions.map(\.id))
    }

    func testNoCandidatesProducesNoPendingPages() {
        XCTAssertTrue(DetectionReviewPage.grouped([], isPDF: true).isEmpty)
        XCTAssertTrue(DetectionReviewPage.grouped([], isPDF: false).isEmpty)
    }
}
