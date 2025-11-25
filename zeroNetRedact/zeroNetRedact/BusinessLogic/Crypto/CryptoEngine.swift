//
//  CryptoEngine.swift
//  ZeroNet Redact
//
//  加密引擎 - 使用AES-256-GCM加密原始文件
//

import CryptoKit
import Foundation
import Security

/// 加密引擎单例
class CryptoEngine {
    static let shared = CryptoEngine()

    private let keychain = KeychainManager()
    private let masterKeyTag = "com.zeronet.redact.masterkey"

    private init() {}

    // MARK: - 主密钥管理

    /// 获取或创建主密钥
    private func getMasterKey() throws -> SymmetricKey {
        // 尝试从Keychain读取
        if let keyData = keychain.readKey(tag: masterKeyTag) {
            return SymmetricKey(data: keyData)
        }

        // 创建新密钥
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        // 保存到Keychain
        try keychain.saveKey(keyData, tag: masterKeyTag)

        return key
    }

    // MARK: - 加密/解密

    /// 加密数据
    /// - Parameter data: 原始数据
    /// - Returns: 加密后的数据（包含nonce和tag）
    func encrypt(data: Data) throws -> Data {
        let key = try getMasterKey()

        // 使用AES-GCM加密
        let sealedBox = try AES.GCM.seal(data, using: key)

        // 组合: nonce(12字节) + ciphertext + tag(16字节)
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        return combined
    }

    /// 解密数据
    /// - Parameter encryptedData: 加密的数据
    /// - Returns: 原始数据
    func decrypt(data encryptedData: Data) throws -> Data {
        let key = try getMasterKey()

        // 从combined格式恢复SealedBox
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)

        // 解密
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        return decryptedData
    }

    // MARK: - 批量操作

    /// 批量加密文件
    func encryptFiles(_ files: [Data]) async throws -> [Data] {
        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, fileData) in files.enumerated() {
                group.addTask {
                    let encrypted = try self.encrypt(data: fileData)
                    return (index, encrypted)
                }
            }

            var results: [Data] = Array(repeating: Data(), count: files.count)
            for try await (index, encrypted) in group {
                results[index] = encrypted
            }
            return results
        }
    }

    /// 批量解密文件
    func decryptFiles(_ files: [Data]) async throws -> [Data] {
        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, encryptedData) in files.enumerated() {
                group.addTask {
                    let decrypted = try self.decrypt(data: encryptedData)
                    return (index, decrypted)
                }
            }

            var results: [Data] = Array(repeating: Data(), count: files.count)
            for try await (index, decrypted) in group {
                results[index] = decrypted
            }
            return results
        }
    }

    // MARK: - 密钥管理

    /// 重置主密钥（慎用！会导致所有已加密数据无法解密）
    func resetMasterKey() throws {
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try keychain.deleteKey(tag: masterKeyTag)
        try keychain.saveKey(keyData, tag: masterKeyTag)
    }

    /// 检查密钥是否存在
    func hasMasterKey() -> Bool {
        return keychain.readKey(tag: masterKeyTag) != nil
    }
}

// MARK: - Keychain管理器

class KeychainManager {

    /// 保存密钥到Keychain
    func saveKey(_ keyData: Data, tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: keyData,
        ]

        // 删除旧密钥（如果存在）
        SecItemDelete(query as CFDictionary)

        // 添加新密钥
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CryptoError.keychainError(status)
        }
    }

    /// 从Keychain读取密钥
    func readKey(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    /// 删除密钥
    func deleteKey(tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CryptoError.keychainError(status)
        }
    }
}

// MARK: - 错误定义

enum CryptoError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case keychainError(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "加密失败"
        case .decryptionFailed:
            return "解密失败"
        case .keychainError(let status):
            return "Keychain错误: \(status)"
        case .invalidData:
            return "无效的数据格式"
        }
    }
}
