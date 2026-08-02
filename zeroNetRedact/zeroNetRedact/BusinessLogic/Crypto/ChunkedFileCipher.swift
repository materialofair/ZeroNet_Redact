import CryptoKit
import Foundation
import Security

/// 大文件认证分块加密。每块独立 AES-GCM，头部和块序号通过 AAD 绑定，支持常量内存处理。
nonisolated final class ChunkedFileCipher: @unchecked Sendable {
    static let shared = ChunkedFileCipher()

    struct EncryptionResult {
        let plaintextSize: Int64
        let sha256: String
    }

    private let magic = Data("ZNRCHNK1".utf8)
    private let version: UInt16 = 1
    private let defaultChunkSize = 4 * 1024 * 1024
    private let maximumChunkSize = 16 * 1024 * 1024

    private init() {}

    func encrypt(
        sourceURL: URL,
        destinationURL: URL,
        chunkSize: Int? = nil,
        shouldCancel: @escaping () -> Bool = { false },
        progress: @escaping (Double) -> Void = { _ in }
    ) throws -> EncryptionResult {
        let selectedChunkSize = chunkSize ?? defaultChunkSize
        guard selectedChunkSize > 0, selectedChunkSize <= maximumChunkSize else {
            throw ChunkedFileCipherError.invalidChunkSize
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        guard let sizeNumber = attributes[.size] as? NSNumber else {
            throw ChunkedFileCipherError.invalidSource
        }
        let plaintextSize = sizeNumber.int64Value
        guard plaintextSize >= 0 else { throw ChunkedFileCipherError.invalidSource }

        let partialURL = destinationURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partialURL)
        FileManager.default.createFile(atPath: partialURL.path, contents: nil)

        do {
            let input = try FileHandle(forReadingFrom: sourceURL)
            let output = try FileHandle(forWritingTo: partialURL)
            defer {
                try? input.close()
                try? output.close()
            }

            let fileNonce = try randomBytes(count: 16)
            let header = makeHeader(
                chunkSize: UInt32(selectedChunkSize),
                plaintextSize: UInt64(plaintextSize),
                fileNonce: fileNonce
            )
            try output.write(contentsOf: header)

            let key = try CryptoEngine.shared.fileEncryptionKey()
            var hasher = SHA256()
            var processed: Int64 = 0
            var index: UInt32 = 0

            while processed < plaintextSize {
                if shouldCancel() { throw CancellationError() }
                let requested = min(Int64(selectedChunkSize), plaintextSize - processed)
                guard let chunk = try input.read(upToCount: Int(requested)), !chunk.isEmpty else {
                    throw ChunkedFileCipherError.unexpectedEndOfFile
                }
                hasher.update(data: chunk)

                let plainLength = UInt32(chunk.count)
                let aad = makeAAD(header: header, index: index, plainLength: plainLength)
                let nonce = try AES.GCM.Nonce(data: derivedNonce(fileNonce: fileNonce, index: index))
                let sealed = try AES.GCM.seal(chunk, using: key, nonce: nonce, authenticating: aad)
                guard let combined = sealed.combined else {
                    throw ChunkedFileCipherError.encryptionFailed
                }

                var recordHeader = Data()
                recordHeader.appendBigEndian(index)
                recordHeader.appendBigEndian(plainLength)
                recordHeader.appendBigEndian(UInt32(combined.count))
                try output.write(contentsOf: recordHeader)
                try output.write(contentsOf: combined)

                processed += Int64(chunk.count)
                let nextIndex = index.addingReportingOverflow(1)
                guard !nextIndex.overflow else { throw ChunkedFileCipherError.integerOverflow }
                index = nextIndex.partialValue
                progress(plaintextSize == 0 ? 1 : Double(processed) / Double(plaintextSize))
            }

            let trailing = try input.read(upToCount: 1) ?? Data()
            guard trailing.isEmpty else { throw ChunkedFileCipherError.sourceChangedDuringRead }
            try output.synchronize()
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: partialURL, to: destinationURL)

            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            progress(1)
            return EncryptionResult(plaintextSize: plaintextSize, sha256: digest)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }
    }

    func decrypt(
        sourceURL: URL,
        destinationURL: URL,
        shouldCancel: @escaping () -> Bool = { false },
        progress: @escaping (Double) -> Void = { _ in }
    ) throws {
        let partialURL = destinationURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partialURL)
        FileManager.default.createFile(atPath: partialURL.path, contents: nil)

        do {
            let input = try FileHandle(forReadingFrom: sourceURL)
            let output = try FileHandle(forWritingTo: partialURL)
            defer {
                try? input.close()
                try? output.close()
            }

            let headerLength = magic.count + 2 + 4 + 8 + 16
            let header = try readExactly(headerLength, from: input)
            let parsed = try parseHeader(header)
            guard parsed.chunkSize > 0, parsed.chunkSize <= maximumChunkSize else {
                throw ChunkedFileCipherError.invalidChunkSize
            }

            let key = try CryptoEngine.shared.fileEncryptionKey()
            var recovered: UInt64 = 0
            var expectedIndex: UInt32 = 0

            while recovered < parsed.plaintextSize {
                if shouldCancel() { throw CancellationError() }
                let record = try readExactly(12, from: input)
                var cursor = DataCursor(data: record)
                let index: UInt32 = try cursor.readBigEndian()
                let plainLength: UInt32 = try cursor.readBigEndian()
                let sealedLength: UInt32 = try cursor.readBigEndian()

                guard index == expectedIndex else { throw ChunkedFileCipherError.invalidChunkOrder }
                guard plainLength > 0, plainLength <= parsed.chunkSize else {
                    throw ChunkedFileCipherError.invalidRecord
                }
                guard sealedLength == plainLength + 28 else {
                    throw ChunkedFileCipherError.invalidRecord
                }
                guard recovered + UInt64(plainLength) <= parsed.plaintextSize else {
                    throw ChunkedFileCipherError.invalidRecord
                }

                let combined = try readExactly(Int(sealedLength), from: input)
                let sealedBox = try AES.GCM.SealedBox(combined: combined)
                let aad = makeAAD(header: header, index: index, plainLength: plainLength)
                let opened: Data
                do {
                    opened = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
                } catch {
                    throw ChunkedFileCipherError.authenticationFailed
                }
                guard opened.count == Int(plainLength) else {
                    throw ChunkedFileCipherError.invalidRecord
                }
                try output.write(contentsOf: opened)

                recovered += UInt64(opened.count)
                let nextIndex = expectedIndex.addingReportingOverflow(1)
                guard !nextIndex.overflow else { throw ChunkedFileCipherError.integerOverflow }
                expectedIndex = nextIndex.partialValue
                progress(parsed.plaintextSize == 0 ? 1 : Double(recovered) / Double(parsed.plaintextSize))
            }

            let trailing = try input.read(upToCount: 1) ?? Data()
            guard trailing.isEmpty else { throw ChunkedFileCipherError.trailingData }
            try output.synchronize()
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: partialURL, to: destinationURL)
            progress(1)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }
    }

    private func makeHeader(chunkSize: UInt32, plaintextSize: UInt64, fileNonce: Data) -> Data {
        var data = magic
        data.appendBigEndian(version)
        data.appendBigEndian(chunkSize)
        data.appendBigEndian(plaintextSize)
        data.append(fileNonce)
        return data
    }

    private func parseHeader(_ data: Data) throws -> (chunkSize: UInt32, plaintextSize: UInt64, fileNonce: Data) {
        var cursor = DataCursor(data: data)
        guard try cursor.read(count: magic.count) == magic else {
            throw ChunkedFileCipherError.invalidHeader
        }
        let fileVersion: UInt16 = try cursor.readBigEndian()
        guard fileVersion == version else { throw ChunkedFileCipherError.unsupportedVersion }
        let chunkSize: UInt32 = try cursor.readBigEndian()
        let plaintextSize: UInt64 = try cursor.readBigEndian()
        let fileNonce = try cursor.read(count: 16)
        guard cursor.isAtEnd else { throw ChunkedFileCipherError.invalidHeader }
        return (chunkSize, plaintextSize, fileNonce)
    }

    private func makeAAD(header: Data, index: UInt32, plainLength: UInt32) -> Data {
        var aad = header
        aad.appendBigEndian(index)
        aad.appendBigEndian(plainLength)
        return aad
    }

    private func derivedNonce(fileNonce: Data, index: UInt32) -> Data {
        var material = fileNonce
        material.appendBigEndian(index)
        return Data(SHA256.hash(data: material).prefix(12))
    }

    private func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw ChunkedFileCipherError.randomGenerationFailed }
        return Data(bytes)
    }

    private func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        guard count >= 0 else { throw ChunkedFileCipherError.invalidRecord }
        var result = Data()
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else {
                throw ChunkedFileCipherError.unexpectedEndOfFile
            }
            result.append(chunk)
        }
        return result
    }
}

enum ChunkedFileCipherError: LocalizedError {
    case invalidSource
    case invalidHeader
    case unsupportedVersion
    case invalidChunkSize
    case invalidRecord
    case invalidChunkOrder
    case unexpectedEndOfFile
    case trailingData
    case sourceChangedDuringRead
    case randomGenerationFailed
    case encryptionFailed
    case authenticationFailed
    case integerOverflow

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return NSLocalizedString("video.error.authenticationFailed", comment: "")
        case .unexpectedEndOfFile, .invalidHeader, .invalidRecord, .invalidChunkOrder, .trailingData:
            return NSLocalizedString("video.error.corruptEncryptedFile", comment: "")
        default:
            return NSLocalizedString("video.error.fileProcessingFailed", comment: "")
        }
    }
}

private nonisolated struct DataCursor {
    let data: Data
    var offset = 0
    var isAtEnd: Bool { offset == data.count }

    mutating func read(count: Int) throws -> Data {
        guard count >= 0, offset <= data.count - count else {
            throw ChunkedFileCipherError.invalidHeader
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readBigEndian<T: FixedWidthInteger>() throws -> T {
        let bytes = try read(count: MemoryLayout<T>.size)
        return bytes.reduce(T.zero) { ($0 << 8) | T($1) }
    }
}

private extension Data {
    nonisolated mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }
}
