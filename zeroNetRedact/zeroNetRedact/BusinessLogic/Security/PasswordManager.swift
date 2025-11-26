import CommonCrypto
import CryptoKit
import Foundation
import Security

/// 密码管理器 - 负责密码的加密、验证、存储
class PasswordManager {
    static let shared = PasswordManager()

    // MARK: - Constants

    private let service = "com.zeronet.redact"
    private let passwordAccount = "app.password.hash"
    private let saltAccount = "app.password.salt"
    private let attemptsKey = "password.failed.attempts"
    private let lockoutKey = "password.lockout.until"

    private let iterations = 200_000  // PBKDF2 迭代次数
    private let keyLength = 32  // 256-bit key
    private let saltLength = 16  // 16 bytes salt

    private let maxAttempts = 5
    private let lockoutDurations: [TimeInterval] = [0, 0, 60, 300, 600]  // 0, 0, 1分钟, 5分钟, 10分钟

    private init() {}

    // MARK: - Public Methods

    /// 检查是否已设置密码
    func hasPassword() -> Bool {
        return readFromKeychain(account: passwordAccount) != nil
    }

    /// 设置密码
    func setPassword(_ password: String) throws {
        guard password.count >= 6 else {
            throw SecurityError.passwordTooShort
        }

        // 生成盐值
        let salt = generateSalt()

        // 派生密钥
        let hash = try deriveKey(from: password, salt: salt)

        // 保存到 Keychain
        try saveToKeychain(data: hash, account: passwordAccount)
        try saveToKeychain(data: salt, account: saltAccount)

        // 重置失败次数
        resetFailedAttempts()
    }

    /// 验证密码
    func verifyPassword(_ password: String) -> Bool {
        guard let storedHash = readFromKeychain(account: passwordAccount),
            let salt = readFromKeychain(account: saltAccount)
        else {
            return false
        }

        do {
            let inputHash = try deriveKey(from: password, salt: salt)

            // 使用常数时间比较防止时序攻击
            let isValid = constantTimeComparison(inputHash, storedHash)

            if isValid {
                resetFailedAttempts()
            }

            return isValid
        } catch {
            return false
        }
    }

    /// 修改密码
    func changePassword(oldPassword: String, newPassword: String) throws {
        // 验证旧密码
        guard verifyPassword(oldPassword) else {
            throw SecurityError.oldPasswordIncorrect
        }

        // 设置新密码
        try setPassword(newPassword)
    }

    /// 移除密码
    func removePassword() throws {
        try deleteFromKeychain(account: passwordAccount)
        try deleteFromKeychain(account: saltAccount)
        resetFailedAttempts()
    }

    /// 评估密码强度
    func evaluateStrength(_ password: String) -> PasswordStrength {
        let length = password.count
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumber = password.contains(where: { $0.isNumber })
        let hasSpecial = password.contains(where: { !$0.isLetter && !$0.isNumber })

        if length < 6 {
            return .weak
        } else if length < 12 {
            return .fair
        } else if length >= 15 && hasUppercase && hasLowercase && hasNumber && hasSpecial {
            return .strong
        } else if (hasNumber || hasSpecial) && (hasUppercase || hasLowercase) {
            return .good
        } else {
            return .fair
        }
    }

    /// 记录失败尝试
    func recordFailedAttempt() {
        let attempts = getFailedAttempts() + 1
        UserDefaults.standard.set(attempts, forKey: attemptsKey)

        // 检查是否需要锁定
        if attempts >= 3 {
            let index = min(attempts - 1, lockoutDurations.count - 1)
            let duration = lockoutDurations[index]
            if duration > 0 {
                let lockoutUntil = Date().addingTimeInterval(duration)
                UserDefaults.standard.set(lockoutUntil.timeIntervalSince1970, forKey: lockoutKey)
            }
        }
    }

    /// 获取剩余尝试次数
    func getRemainingAttempts() -> Int {
        return max(0, maxAttempts - getFailedAttempts())
    }

    /// 检查是否被锁定
    func isLocked() -> (locked: Bool, until: Date?) {
        guard let timestamp = UserDefaults.standard.object(forKey: lockoutKey) as? TimeInterval
        else {
            return (false, nil)
        }

        let lockoutUntil = Date(timeIntervalSince1970: timestamp)

        if lockoutUntil > Date() {
            return (true, lockoutUntil)
        } else {
            // 锁定期已过，清除锁定
            UserDefaults.standard.removeObject(forKey: lockoutKey)
            return (false, nil)
        }
    }

    // MARK: - Private Methods

    /// 生成随机盐值
    private func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// 使用 PBKDF2 派生密钥
    private func deriveKey(from password: String, salt: Data) throws -> Data {
        guard let passwordData = password.data(using: .utf8) else {
            throw SecurityError.invalidPassword
        }

        var derivedKeyData = Data(count: keyLength)

        let derivationStatus = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard derivationStatus == kCCSuccess else {
            throw SecurityError.invalidPassword
        }

        return derivedKeyData
    }

    /// 常数时间比较（防止时序攻击）
    private func constantTimeComparison(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }

        var result: UInt8 = 0
        for (byte1, byte2) in zip(lhs, rhs) {
            result |= byte1 ^ byte2
        }

        return result == 0
    }

    /// 保存到 Keychain
    private func saveToKeychain(data: Data, account: String) throws {
        // 先删除旧数据
        try? deleteFromKeychain(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw SecurityError.keychainError(status)
        }
    }

    /// 从 Keychain 读取
    private func readFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }

    /// 从 Keychain 删除
    private func deleteFromKeychain(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]

        let status = SecItemDelete(query as CFDictionary)

        // errSecItemNotFound 不算错误
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityError.keychainError(status)
        }
    }

    /// 获取失败次数
    private func getFailedAttempts() -> Int {
        return UserDefaults.standard.integer(forKey: attemptsKey)
    }

    /// 重置失败次数
    private func resetFailedAttempts() {
        UserDefaults.standard.removeObject(forKey: attemptsKey)
        UserDefaults.standard.removeObject(forKey: lockoutKey)
    }
}
