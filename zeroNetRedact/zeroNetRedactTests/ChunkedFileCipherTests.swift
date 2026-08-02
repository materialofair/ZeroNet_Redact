import XCTest
@testable import zeroNetRedact

final class ChunkedFileCipherTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChunkedFileCipherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testRoundTripAcrossMultipleChunks() throws {
        let source = directory.appendingPathComponent("source.bin")
        let encrypted = directory.appendingPathComponent("source.enc")
        let decrypted = directory.appendingPathComponent("decrypted.bin")
        let original = Data((0..<(256 * 1024 + 37)).map { UInt8($0 % 251) })
        try original.write(to: source)

        let result = try ChunkedFileCipher.shared.encrypt(
            sourceURL: source,
            destinationURL: encrypted,
            chunkSize: 64 * 1024
        )
        try ChunkedFileCipher.shared.decrypt(sourceURL: encrypted, destinationURL: decrypted)

        XCTAssertEqual(result.plaintextSize, Int64(original.count))
        XCTAssertEqual(result.sha256.count, 64)
        XCTAssertEqual(try Data(contentsOf: decrypted), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: encrypted.appendingPathExtension("partial").path))
    }

    func testEmptyFileRoundTrip() throws {
        let source = directory.appendingPathComponent("empty.bin")
        let encrypted = directory.appendingPathComponent("empty.enc")
        let decrypted = directory.appendingPathComponent("empty.out")
        try Data().write(to: source)

        _ = try ChunkedFileCipher.shared.encrypt(sourceURL: source, destinationURL: encrypted)
        try ChunkedFileCipher.shared.decrypt(sourceURL: encrypted, destinationURL: decrypted)

        XCTAssertEqual(try Data(contentsOf: decrypted), Data())
    }

    func testTamperedCiphertextIsRejectedAndPartialOutputRemoved() throws {
        let source = directory.appendingPathComponent("source.bin")
        let encrypted = directory.appendingPathComponent("source.enc")
        let decrypted = directory.appendingPathComponent("decrypted.bin")
        try Data(repeating: 0x5A, count: 100_000).write(to: source)
        _ = try ChunkedFileCipher.shared.encrypt(
            sourceURL: source,
            destinationURL: encrypted,
            chunkSize: 32 * 1024
        )

        var bytes = try Data(contentsOf: encrypted)
        bytes[bytes.count - 8] ^= 0xFF
        try bytes.write(to: encrypted, options: .atomic)

        XCTAssertThrowsError(
            try ChunkedFileCipher.shared.decrypt(sourceURL: encrypted, destinationURL: decrypted)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: decrypted.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: decrypted.appendingPathExtension("partial").path))
    }

    func testTruncatedCiphertextIsRejected() throws {
        let source = directory.appendingPathComponent("source.bin")
        let encrypted = directory.appendingPathComponent("source.enc")
        let decrypted = directory.appendingPathComponent("decrypted.bin")
        try Data(repeating: 0xA5, count: 90_000).write(to: source)
        _ = try ChunkedFileCipher.shared.encrypt(
            sourceURL: source,
            destinationURL: encrypted,
            chunkSize: 32 * 1024
        )

        let full = try Data(contentsOf: encrypted)
        try Data(full.dropLast(40)).write(to: encrypted, options: .atomic)

        XCTAssertThrowsError(
            try ChunkedFileCipher.shared.decrypt(sourceURL: encrypted, destinationURL: decrypted)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: decrypted.path))
    }
}
