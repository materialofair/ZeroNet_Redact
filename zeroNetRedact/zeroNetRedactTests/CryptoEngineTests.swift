//
//  CryptoEngineTests.swift
//  ZeroNet Redact Tests
//
//  加密引擎单元测试
//

import XCTest
import CryptoKit
@testable import zeroNetRedact

final class CryptoEngineTests: XCTestCase {

    var cryptoEngine: CryptoEngine!

    override func setUp() {
        super.setUp()
        cryptoEngine = CryptoEngine.shared
    }

    override func tearDown() {
        // 清理测试数据
        try? cryptoEngine.resetMasterKey()
        super.tearDown()
    }

    // MARK: - 加密/解密往返测试

    /// 测试基本的加密解密往返
    func testEncryptDecryptRoundtrip() throws {
        // Given: 准备测试数据
        let originalData = "这是测试数据".data(using: .utf8)!

        // When: 加密然后解密
        let encryptedData = try cryptoEngine.encrypt(data: originalData)
        let decryptedData = try cryptoEngine.decrypt(data: encryptedData)

        // Then: 解密后的数据应该与原始数据相同
        XCTAssertEqual(originalData, decryptedData, "解密后的数据应该与原始数据相同")
    }

    /// 测试空数据的加密解密
    func testEncryptDecryptEmptyData() throws {
        // Given: 空数据
        let emptyData = Data()

        // When: 加密然后解密
        let encryptedData = try cryptoEngine.encrypt(data: emptyData)
        let decryptedData = try cryptoEngine.decrypt(data: encryptedData)

        // Then: 解密后应该还是空数据
        XCTAssertEqual(emptyData, decryptedData, "空数据加密解密后应该保持为空")
    }

    /// 测试大数据的加密解密 (模拟图片数据)
    func testEncryptDecryptLargeData() throws {
        // Given: 1MB 的随机数据 (模拟图片)
        var largeData = Data(count: 1024 * 1024)
        largeData.withUnsafeMutableBytes { ptr in
            arc4random_buf(ptr.baseAddress!, 1024 * 1024)
        }

        // When: 加密然后解密
        let encryptedData = try cryptoEngine.encrypt(data: largeData)
        let decryptedData = try cryptoEngine.decrypt(data: encryptedData)

        // Then: 大数据加密解密后应该保持一致
        XCTAssertEqual(largeData, decryptedData, "大数据加密解密后应该保持一致")
    }

    /// 测试加密后的数据不等于原始数据
    func testEncryptedDataDiffersFromOriginal() throws {
        // Given: 测试数据
        let originalData = "敏感数据".data(using: .utf8)!

        // When: 加密
        let encryptedData = try cryptoEngine.encrypt(data: originalData)

        // Then: 加密后的数据应该与原始数据不同
        XCTAssertNotEqual(originalData, encryptedData, "加密后的数据不应该等于原始数据")
    }

    /// 测试多次加密产生不同的密文 (因为 nonce 不同)
    func testMultipleEncryptionsProduceDifferentCiphertext() throws {
        // Given: 相同的原始数据
        let originalData = "测试数据".data(using: .utf8)!

        // When: 两次加密
        let encryptedData1 = try cryptoEngine.encrypt(data: originalData)
        let encryptedData2 = try cryptoEngine.encrypt(data: originalData)

        // Then: 两次加密的结果应该不同 (因为 nonce 随机)
        XCTAssertNotEqual(encryptedData1, encryptedData2, "相同数据的多次加密应该产生不同的密文")

        // But: 两次加密的数据都应该能正确解密
        let decryptedData1 = try cryptoEngine.decrypt(data: encryptedData1)
        let decryptedData2 = try cryptoEngine.decrypt(data: encryptedData2)
        XCTAssertEqual(originalData, decryptedData1)
        XCTAssertEqual(originalData, decryptedData2)
    }

    // MARK: - 错误处理测试

    /// 测试解密无效数据
    func testDecryptInvalidData() {
        // Given: 无效的加密数据
        let invalidData = "这不是有效的加密数据".data(using: .utf8)!

        // When & Then: 解密应该失败
        XCTAssertThrowsError(try cryptoEngine.decrypt(data: invalidData)) { error in
            // 验证错误类型
            XCTAssertTrue(error is CryptoKitError, "应该抛出 CryptoKit 错误")
        }
    }

    /// 测试解密被篡改的数据
    func testDecryptTamperedData() throws {
        // Given: 正常加密的数据
        let originalData = "敏感数据".data(using: .utf8)!
        var encryptedData = try cryptoEngine.encrypt(data: originalData)

        // When: 篡改加密数据 (修改最后一个字节)
        encryptedData[encryptedData.count - 1] ^= 0xFF

        // Then: 解密应该失败 (GCM 认证失败)
        XCTAssertThrowsError(try cryptoEngine.decrypt(data: encryptedData)) { error in
            XCTAssertTrue(error is CryptoKitError, "篡改的数据应该导致认证失败")
        }
    }

    /// 测试解密过短的数据
    func testDecryptTooShortData() {
        // Given: 太短的数据 (小于 nonce + tag 的长度)
        let tooShortData = Data([0x01, 0x02, 0x03])

        // When & Then: 解密应该失败
        XCTAssertThrowsError(try cryptoEngine.decrypt(data: tooShortData)) { error in
            XCTAssertTrue(error is CryptoKitError, "数据太短应该导致解密失败")
        }
    }

    // MARK: - Keychain 集成测试

    /// 测试主密钥的持久化
    func testMasterKeyPersistence() throws {
        // Given: 加密一些数据 (会创建主密钥)
        let testData = "测试数据".data(using: .utf8)!
        let encryptedData = try cryptoEngine.encrypt(data: testData)

        // When: 检查主密钥是否存在
        let hasMasterKey = cryptoEngine.hasMasterKey()

        // Then: 主密钥应该存在
        XCTAssertTrue(hasMasterKey, "主密钥应该被持久化到 Keychain")

        // And: 应该能用持久化的密钥解密数据
        let decryptedData = try cryptoEngine.decrypt(data: encryptedData)
        XCTAssertEqual(testData, decryptedData)
    }

    /// 测试重置主密钥
    func testResetMasterKey() throws {
        // Given: 使用旧密钥加密数据
        let testData = "敏感数据".data(using: .utf8)!
        let encryptedWithOldKey = try cryptoEngine.encrypt(data: testData)

        // When: 重置主密钥
        try cryptoEngine.resetMasterKey()

        // Then: 用旧密钥加密的数据无法解密
        XCTAssertThrowsError(try cryptoEngine.decrypt(data: encryptedWithOldKey)) { error in
            XCTAssertTrue(error is CryptoKitError, "旧密钥加密的数据应该无法用新密钥解密")
        }

        // But: 新密钥可以正常工作
        let encryptedWithNewKey = try cryptoEngine.encrypt(data: testData)
        let decryptedData = try cryptoEngine.decrypt(data: encryptedWithNewKey)
        XCTAssertEqual(testData, decryptedData, "新密钥应该能正常工作")
    }

    // MARK: - 批量操作测试

    /// 测试批量加密
    func testBatchEncryption() async throws {
        // Given: 多个文件数据
        let files = [
            "文件1内容".data(using: .utf8)!,
            "文件2内容".data(using: .utf8)!,
            "文件3内容".data(using: .utf8)!,
            "文件4内容".data(using: .utf8)!,
            "文件5内容".data(using: .utf8)!
        ]

        // When: 批量加密
        let encryptedFiles = try await cryptoEngine.encryptFiles(files)

        // Then: 应该得到相同数量的加密文件
        XCTAssertEqual(files.count, encryptedFiles.count, "批量加密应该返回相同数量的文件")

        // And: 每个加密文件都应该能正确解密
        for (index, encryptedData) in encryptedFiles.enumerated() {
            let decryptedData = try cryptoEngine.decrypt(data: encryptedData)
            XCTAssertEqual(files[index], decryptedData, "批量加密的文件应该能正确解密")
        }
    }

    /// 测试批量解密
    func testBatchDecryption() async throws {
        // Given: 多个加密文件
        let originalFiles = [
            "文件A".data(using: .utf8)!,
            "文件B".data(using: .utf8)!,
            "文件C".data(using: .utf8)!
        ]

        let encryptedFiles = try await cryptoEngine.encryptFiles(originalFiles)

        // When: 批量解密
        let decryptedFiles = try await cryptoEngine.decryptFiles(encryptedFiles)

        // Then: 解密后的文件应该与原始文件相同
        XCTAssertEqual(originalFiles.count, decryptedFiles.count)
        for (index, decryptedData) in decryptedFiles.enumerated() {
            XCTAssertEqual(originalFiles[index], decryptedData, "批量解密应该恢复原始数据")
        }
    }

    /// 测试批量操作保持顺序
    func testBatchOperationsMaintainOrder() async throws {
        // Given: 带序号的文件
        let files = (0..<10).map { "文件\($0)".data(using: .utf8)! }

        // When: 批量加密再批量解密
        let encryptedFiles = try await cryptoEngine.encryptFiles(files)
        let decryptedFiles = try await cryptoEngine.decryptFiles(encryptedFiles)

        // Then: 顺序应该保持不变
        for (index, decryptedData) in decryptedFiles.enumerated() {
            XCTAssertEqual(files[index], decryptedData, "批量操作应该保持文件顺序")
        }
    }

    // MARK: - 性能测试

    /// 测试加密性能
    func testEncryptionPerformance() throws {
        // Given: 1MB 的测试数据
        var testData = Data(count: 1024 * 1024)
        testData.withUnsafeMutableBytes { ptr in
            arc4random_buf(ptr.baseAddress!, 1024 * 1024)
        }

        // Measure: 加密性能
        measure {
            _ = try? cryptoEngine.encrypt(data: testData)
        }
    }

    /// 测试解密性能
    func testDecryptionPerformance() throws {
        // Given: 预先加密的 1MB 数据
        var testData = Data(count: 1024 * 1024)
        testData.withUnsafeMutableBytes { ptr in
            arc4random_buf(ptr.baseAddress!, 1024 * 1024)
        }
        let encryptedData = try cryptoEngine.encrypt(data: testData)

        // Measure: 解密性能
        measure {
            _ = try? cryptoEngine.decrypt(data: encryptedData)
        }
    }
}
