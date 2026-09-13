import CryptoKit
import XCTest
@testable import zeroNetRedact

final class ShareInboxTests: XCTestCase {
    func testEncryptedRoundTripTamperAndWrongKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = ShareInbox(directory: directory, key: SymmetricKey(size: .bits256))
        let secret = Data("private attachment".utf8)
        try inbox.enqueue(data: secret, type: "com.adobe.pdf")
        let entry = try XCTUnwrap(inbox.entries().first)
        XCTAssertEqual(try inbox.read(entry).data, secret)
        var sealed = try Data(contentsOf: entry)
        XCTAssertNil(sealed.range(of: secret))
        XCTAssertThrowsError(try ShareInbox(directory: directory, key: SymmetricKey(size: .bits256)).read(entry))
        sealed[sealed.count / 2] ^= 1
        try sealed.write(to: entry)
        XCTAssertThrowsError(try inbox.read(entry))
    }

    func testRejectsUnsupportedAndOversizedPayloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = ShareInbox(directory: directory, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try inbox.enqueue(data: Data([1]), type: "public.movie"))
        XCTAssertThrowsError(try inbox.enqueue(data: Data(), type: "public.image"))
        XCTAssertThrowsError(try inbox.enqueue(data: Data(count: ShareInbox.maximumBytes + 1), type: "public.image"))
        XCTAssertTrue(try inbox.entries().isEmpty)
    }
}
