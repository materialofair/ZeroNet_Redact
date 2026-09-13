import CryptoKit
import Foundation
import Security

/// Shared with the extension. The vault master key never leaves the containing app.
nonisolated struct ShareInbox {
    static let groupID = "group.zeronet.redact"
    static let maximumAttachments = 10
    static let maximumBytes = 15 * 1024 * 1024

    nonisolated struct Payload: Codable, Sendable {
        let version: Int
        let type: String
        let data: Data
    }

    let directory: URL
    private let key: SymmetricKey

    init(directory: URL, key: SymmetricKey) {
        self.directory = directory
        self.key = key
    }

    static func live() throws -> ShareInbox {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { throw InboxError.unavailable }
        return ShareInbox(directory: container.appendingPathComponent("ShareInbox", isDirectory: true),
                          key: try sharedKey())
    }

    func enqueue(data: Data, type: String) throws {
        guard ["public.image", "com.adobe.pdf"].contains(type) else { throw InboxError.unsupported }
        guard !data.isEmpty, data.count <= Self.maximumBytes else { throw InboxError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(Payload(version: 1, type: type, data: data))
        let encrypted = try AES.GCM.seal(payload, using: key).combined!
        try encrypted.write(to: directory.appendingPathComponent(UUID().uuidString + ".inbox"),
                            options: [.atomic, .completeFileProtection])
    }

    func entries() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "inbox" }
            .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                < ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
    }

    func read(_ url: URL) throws -> Payload {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumBytes + 4096 else { throw InboxError.tooLarge }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let payload = try PropertyListDecoder().decode(Payload.self, from: AES.GCM.open(sealed, using: key))
        guard payload.version == 1, ["public.image", "com.adobe.pdf"].contains(payload.type),
              !payload.data.isEmpty, payload.data.count <= Self.maximumBytes else { throw InboxError.unsupported }
        return payload
    }

    private static func sharedKey() throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "zeronet.share.inbox.v1", kSecAttrAccount as String: "encryption",
            kSecAttrAccessGroup as String: groupID]
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw InboxError.unavailable }
        let key = SymmetricKey(size: .bits256)
        var addQuery = query
        addQuery[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem { return try sharedKey() }
        guard addStatus == errSecSuccess else { throw InboxError.unavailable }
        return key
    }

    enum InboxError: LocalizedError {
        case unavailable, unsupported, tooLarge
        var errorDescription: String? {
            switch self {
            case .unavailable: return NSLocalizedString("share.error.unavailable", value: "Shared storage is unavailable. Unlock your device and try again.", comment: "")
            case .unsupported: return NSLocalizedString("share.error.unsupported", value: "Only images and PDF files are supported.", comment: "")
            case .tooLarge: return NSLocalizedString("share.error.size", value: "Each attachment must be nonempty and no larger than 15 MB.", comment: "")
            }
        }
    }
}
