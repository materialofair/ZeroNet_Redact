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

    // CRITICAL-5: 失败次数与锁定状态改存 Keychain（避免卸载/重装 App 后 UserDefaults 被清零绕过锁定）
    private let attemptsAccount = "app.password.attempts"
    private let lockoutUntilAccount = "app.password.lockout.until"
    private let lockoutSetUptimeAccount = "app.password.lockout.setUptime"
    private let lockoutDeadlineUptimeAccount = "app.password.lockout.deadlineUptime"

    // 旧版 UserDefaults key，仅用于一次性迁移到 Keychain，迁移完成后即删除
    private let legacyAttemptsKey = "password.failed.attempts"
    private let legacyLockoutKey = "password.lockout.until"

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
        try? saveToKeychain(data: dataFromInt(attempts), account: attemptsAccount)

        // 检查是否需要锁定
        if attempts >= 3 {
            let duration = durationForAttempt(attempts)
            if duration > 0 {
                persistLockout(duration: duration)
            }
        }
    }

    /// 获取剩余尝试次数
    func getRemainingAttempts() -> Int {
        return max(0, maxAttempts - getFailedAttempts())
    }

    /// 距离下一次锁定还需的失败次数与对应锁定时长
    /// - Returns: (再失败多少次将触发锁定, 该次锁定的时长)。当前实现下总能找到下一个锁定阈值
    func nextLockoutThreshold() -> (attemptsUntilLockout: Int, duration: TimeInterval)? {
        let currentAttempts = getFailedAttempts()
        for offset in 1...lockoutDurations.count {
            let duration = durationForAttempt(currentAttempts + offset)
            if duration > 0 {
                return (offset, duration)
            }
        }
        return nil
    }

    /// 检查是否被锁定
    ///
    /// CRITICAL-4: 锁定判定同时参考墙钟截止时间与单调时钟（`ProcessInfo.systemUptime`，即系统开机后
    /// 已运行的时长）截止时间，取两者剩余时间中更长者——用户把系统时间调快后，墙钟判定会失效，
    /// 但单调时钟不受墙钟调整影响，仍维持锁定。
    ///
    /// - Note: `systemUptime` 会在设备重启后归零重新计数。若检测到当前值小于锁定记录时的值，
    ///   说明期间发生过重启，单调参照已失效，此时退回仅墙钟判定——重启本身已构成成本与攻击阻力，
    ///   这里选择在该场景下相信墙钟结果，是复杂度与安全性之间的合理折衷。
    func isLocked() -> (locked: Bool, until: Date?) {
        guard let record = readLockoutRecord() else {
            return (false, nil)
        }

        let wallRemaining = record.until.timeIntervalSinceNow
        let currentUptime = ProcessInfo.processInfo.systemUptime

        let remaining: TimeInterval
        if currentUptime < record.setUptime {
            // 单调时钟比记录时更小，说明设备已重启，单调参照失效，退回墙钟判定
            remaining = wallRemaining
        } else {
            let monotonicRemaining = record.deadlineUptime - currentUptime
            remaining = max(wallRemaining, monotonicRemaining)
        }

        if remaining > 0 {
            return (true, Date().addingTimeInterval(remaining))
        } else {
            // 锁定期已过，清除锁定记录
            clearLockoutRecord()
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

    /// 计算给定失败次数对应的锁定时长（0 表示不触发锁定）
    private func durationForAttempt(_ attempts: Int) -> TimeInterval {
        guard attempts > 0 else { return 0 }
        let index = min(attempts - 1, lockoutDurations.count - 1)
        return lockoutDurations[index]
    }

    /// 获取失败次数（Keychain 优先，兼容迁移旧版 UserDefaults 数据）
    private func getFailedAttempts() -> Int {
        if let data = readFromKeychain(account: attemptsAccount), let count = intFromData(data) {
            return count
        }

        // 兼容旧版 UserDefaults 失败次数：迁移一次后删除，保留原值避免误清零导致提前/延后锁定
        if let legacyCount = UserDefaults.standard.object(forKey: legacyAttemptsKey) as? Int {
            try? saveToKeychain(data: dataFromInt(legacyCount), account: attemptsAccount)
            UserDefaults.standard.removeObject(forKey: legacyAttemptsKey)
            return legacyCount
        }

        return 0
    }

    /// 重置失败次数与锁定状态（Keychain + 清理旧版 UserDefaults 残留）
    private func resetFailedAttempts() {
        try? deleteFromKeychain(account: attemptsAccount)
        UserDefaults.standard.removeObject(forKey: legacyAttemptsKey)
        clearLockoutRecord()
    }

    /// 读取当前锁定记录（Keychain 优先，兼容迁移旧版 UserDefaults 数据）
    private func readLockoutRecord() -> (
        until: Date, setUptime: TimeInterval, deadlineUptime: TimeInterval
    )? {
        if let untilData = readFromKeychain(account: lockoutUntilAccount),
            let untilTS = doubleFromData(untilData),
            let setUptimeData = readFromKeychain(account: lockoutSetUptimeAccount),
            let setUptime = doubleFromData(setUptimeData),
            let deadlineData = readFromKeychain(account: lockoutDeadlineUptimeAccount),
            let deadlineUptime = doubleFromData(deadlineData)
        {
            return (Date(timeIntervalSince1970: untilTS), setUptime, deadlineUptime)
        }

        // 兼容旧版 UserDefaults 锁定记录：旧数据没有单调参照，以当前系统运行时长为基准重建，
        // 迁移一次后删除
        if let legacyTS = UserDefaults.standard.object(forKey: legacyLockoutKey) as? Double {
            let until = Date(timeIntervalSince1970: legacyTS)
            let remaining = max(0, until.timeIntervalSinceNow)
            let setUptime = ProcessInfo.processInfo.systemUptime
            let deadlineUptime = setUptime + remaining
            persistLockout(until: until, setUptime: setUptime, deadlineUptime: deadlineUptime)
            UserDefaults.standard.removeObject(forKey: legacyLockoutKey)
            return (until, setUptime, deadlineUptime)
        }

        return nil
    }

    /// 写入新的锁定记录（基于当前时刻与锁定时长）
    private func persistLockout(duration: TimeInterval) {
        let setUptime = ProcessInfo.processInfo.systemUptime
        let until = Date().addingTimeInterval(duration)
        persistLockout(until: until, setUptime: setUptime, deadlineUptime: setUptime + duration)
    }

    /// 写入锁定记录：同时保存墙钟截止时间与单调时钟参照
    private func persistLockout(until: Date, setUptime: TimeInterval, deadlineUptime: TimeInterval)
    {
        try? saveToKeychain(
            data: dataFromDouble(until.timeIntervalSince1970), account: lockoutUntilAccount)
        try? saveToKeychain(data: dataFromDouble(setUptime), account: lockoutSetUptimeAccount)
        try? saveToKeychain(
            data: dataFromDouble(deadlineUptime), account: lockoutDeadlineUptimeAccount)
    }

    /// 清除锁定记录（Keychain + 旧版 UserDefaults 残留）
    private func clearLockoutRecord() {
        try? deleteFromKeychain(account: lockoutUntilAccount)
        try? deleteFromKeychain(account: lockoutSetUptimeAccount)
        try? deleteFromKeychain(account: lockoutDeadlineUptimeAccount)
        UserDefaults.standard.removeObject(forKey: legacyLockoutKey)
    }

    // MARK: - Byte Encoding Helpers

    private func dataFromDouble(_ value: Double) -> Data {
        withUnsafeBytes(of: value) { Data($0) }
    }

    private func doubleFromData(_ data: Data) -> Double? {
        // Keychain 返回的 Data 不保证按 8 字节对齐，使用 loadUnaligned 避免潜在的对齐问题
        guard data.count == MemoryLayout<Double>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
    }

    private func dataFromInt(_ value: Int) -> Data {
        withUnsafeBytes(of: value) { Data($0) }
    }

    private func intFromData(_ data: Data) -> Int? {
        guard data.count == MemoryLayout<Int>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Int.self) }
    }
}
