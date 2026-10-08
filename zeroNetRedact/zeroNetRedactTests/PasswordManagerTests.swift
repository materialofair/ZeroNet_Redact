import Foundation
import Security
import XCTest
@testable import zeroNetRedact

@MainActor
final class PasswordManagerTests: XCTestCase {
    private let credentialAccount = "app.password.credential.v1"
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: FaultKeychain!
    private var manager: PasswordManager!

    override func setUp() {
        super.setUp()
        suite = "password-tests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        store = FaultKeychain()
        manager = PasswordManager(service: suite, keychain: store.operations, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // Independent PBKDF2-HMAC-SHA256 fixture (200,000 iterations), generated with Python hashlib.
    private func seedLegacy() {
        store.items["app.password.hash"] = Data(base64Encoded: "JiRmsa9NOKyK0MaLZhrk+EiQjYVwmH+/iYFTQD88Ci8=")!
        store.items["app.password.salt"] = Data(base64Encoded: "AAECAwQFBgcICQoLDA0ODw==")!
    }

    func testNormalPasswordRoundTripAndChange() throws {
        try manager.setPassword("测试口令2468.10")
        XCTAssertTrue(try manager.hasPassword())
        XCTAssertTrue(try manager.verifyPassword("测试口令2468.10"))
        XCTAssertFalse(try manager.verifyPassword("incorrect"))
        try manager.changePassword(oldPassword: "测试口令2468.10", newPassword: "ChangedPass84")
        XCTAssertTrue(try manager.verifyPassword("ChangedPass84"))
        XCTAssertFalse(try manager.verifyPassword("测试口令2468.10"))
        XCTAssertNotNil(store.items[credentialAccount])
        XCTAssertNil(store.items["app.password.hash"])
        XCTAssertNil(store.items["app.password.salt"])
    }

    func testFailedUpdatePreservesOldPassword() throws {
        try manager.setPassword("InitialPass42")
        store.writeError = errSecIO
        XCTAssertThrowsError(try manager.changePassword(oldPassword: "InitialPass42", newPassword: "ChangedPass84"))
        store.writeError = nil
        XCTAssertTrue(try manager.hasPassword())
        XCTAssertTrue(try manager.verifyPassword("InitialPass42"))
        XCTAssertFalse(try manager.verifyPassword("ChangedPass84"))
    }

    func testFailedLegacyChangePreservesOriginalPair() throws {
        seedLegacy()
        let original = store.items
        store.addError = errSecIO
        XCTAssertThrowsError(try manager.changePassword(oldPassword: "LegacyPass42", newPassword: "ChangedPass84"))
        XCTAssertEqual(store.items, original)
        XCTAssertTrue(try manager.verifyPassword("LegacyPass42"))
        XCTAssertFalse(try manager.verifyPassword("ChangedPass84"))
    }

    func testLegacyLoginMigratesAfterSuccessfulVerification() throws {
        seedLegacy()
        XCTAssertTrue(try manager.hasPassword())
        XCTAssertFalse(try manager.verifyPassword("incorrect"))
        XCTAssertNil(store.items[credentialAccount])
        XCTAssertTrue(try manager.verifyPassword("LegacyPass42"))
        XCTAssertNotNil(store.items[credentialAccount])
        XCTAssertNil(store.items["app.password.hash"])
        XCTAssertNil(store.items["app.password.salt"])
        XCTAssertTrue(try manager.verifyPassword("LegacyPass42"))
    }

    func testFailedMigrationStillAllowsLegacyLoginAndRetries() throws {
        seedLegacy()
        let original = store.items
        store.addError = errSecIO
        XCTAssertTrue(try manager.verifyPassword("LegacyPass42"))
        XCTAssertEqual(store.items, original)
        store.addError = nil
        XCTAssertTrue(try manager.verifyPassword("LegacyPass42"))
        XCTAssertNotNil(store.items[credentialAccount])
    }

    func testReadErrorIsNotMissingPasswordOrWrongPassword() {
        store.readError = errSecInteractionNotAllowed
        XCTAssertThrowsError(try manager.hasPassword())
        XCTAssertThrowsError(try manager.verifyPassword("InitialPass42"))
    }

    func testFailedFirstSaveDoesNotCreatePartialCredentials() {
        store.addError = errSecIO
        XCTAssertThrowsError(try manager.setPassword("InitialPass42"))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(try manager.hasPassword())
    }

    func testStartupNeverDisablesExistingPasswordProtection() {
        let standard = UserDefaults.standard
        let prior = standard.object(forKey: "passwordEnabled")
        standard.set(true, forKey: "passwordEnabled")
        defer {
            if let prior { standard.set(prior, forKey: "passwordEnabled") }
            else { standard.removeObject(forKey: "passwordEnabled") }
        }
        let state = AppState()
        XCTAssertTrue(state.passwordEnabled)
        XCTAssertTrue(state.shouldAuthenticate())
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertTrue(state.isLocked)
    }

    func testUnreadableCredentialsDoNotConsumeLoginAttempts() async {
        let viewModel = AuthenticationViewModel(passwordManager: manager)
        store.readError = errSecInteractionNotAllowed
        viewModel.passwordInput = "InitialPass42"
        let result = await viewModel.verifyPassword()
        XCTAssertFalse(result)
        XCTAssertFalse(viewModel.isVerifying)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.remainingAttempts, 5)
        XCTAssertNil(store.items["app.password.attempts"])
    }

    func testIncompleteLegacyRecordIsAnError() {
        seedLegacy()
        store.items.removeValue(forKey: "app.password.salt")
        XCTAssertThrowsError(try manager.hasPassword())
        XCTAssertThrowsError(try manager.verifyPassword("LegacyPass42"))
    }

    func testCorruptNewRecordCannotFallBackToObsoleteLegacyPassword() {
        seedLegacy()
        store.items[credentialAccount] = Data([1, 2, 3])
        XCTAssertThrowsError(try manager.verifyPassword("LegacyPass42"))
    }

    func testNewRecordRemainsAuthoritativeWhenLegacyCleanupFails() throws {
        seedLegacy()
        store.deleteError = errSecIO
        try manager.changePassword(oldPassword: "LegacyPass42", newPassword: "ChangedPass84")
        XCTAssertNotNil(store.items["app.password.hash"])
        XCTAssertTrue(try manager.verifyPassword("ChangedPass84"))
        XCTAssertFalse(try manager.verifyPassword("LegacyPass42"))
    }

    func testRemovingPasswordDeletesBothFormats() throws {
        seedLegacy()
        store.deleteError = errSecIO
        try manager.setPassword("ChangedPass84")
        store.deleteError = nil
        try manager.removePassword()
        XCTAssertFalse(try manager.hasPassword())
        XCTAssertNil(store.items[credentialAccount])
        XCTAssertNil(store.items["app.password.hash"])
        XCTAssertNil(store.items["app.password.salt"])
    }

    func testRealKeychainSurvivesManagerRecreationAndPasswordChange() throws {
        let service = "password-integration-" + UUID().uuidString
        let live = PasswordManager(service: service, defaults: defaults)
        defer { try? live.removePassword() }
        try live.setPassword("InitialPass42")
        let reopened = PasswordManager(service: service, defaults: defaults)
        XCTAssertTrue(try reopened.verifyPassword("InitialPass42"))
        try reopened.changePassword(oldPassword: "InitialPass42", newPassword: "ChangedPass84")
        XCTAssertTrue(try live.verifyPassword("ChangedPass84"))
        XCTAssertFalse(try live.verifyPassword("InitialPass42"))
    }
}

@MainActor
private final class FaultKeychain {
    var items: [String: Data] = [:]
    var readError: OSStatus?
    var writeError: OSStatus?
    var addError: OSStatus?
    var deleteError: OSStatus?

    private func account(_ query: CFDictionary) -> String {
        (query as! [String: Any])[kSecAttrAccount as String] as! String
    }

    var operations: PasswordKeychainOperations {
        PasswordKeychainOperations(
            read: { query, result in
                if let error = self.readError { return error }
                guard let data = self.items[self.account(query)] else { return errSecItemNotFound }
                result?.pointee = data as NSData
                return errSecSuccess
            },
            add: { query, _ in
                if let error = self.addError { return error }
                if let error = self.writeError { return error }
                let account = self.account(query)
                guard self.items[account] == nil else { return errSecDuplicateItem }
                self.items[account] = (query as! [String: Any])[kSecValueData as String] as? Data
                return errSecSuccess
            },
            update: { query, attributes in
                if let error = self.writeError { return error }
                let account = self.account(query)
                guard self.items[account] != nil else { return errSecItemNotFound }
                self.items[account] = (attributes as! [String: Any])[kSecValueData as String] as? Data
                return errSecSuccess
            },
            delete: { query in
                if let error = self.deleteError { return error }
                return self.items.removeValue(forKey: self.account(query)) == nil ? errSecItemNotFound : errSecSuccess
            }
        )
    }
}
