//
//  StorageManagerTests.swift
//  ZeroNet Redact Tests
//
//  存储管理器单元测试
//

import XCTest
@testable import zeroNetRedact

final class StorageManagerTests: XCTestCase {

    var storageManager: StorageManager!
    var testFileIDs: [UUID] = []

    override func setUp() {
        super.setUp()
        storageManager = StorageManager.shared
        testFileIDs = []
    }

    override func tearDown() {
        // 清理测试创建的文件
        for fileID in testFileIDs {
            try? storageManager.deleteOriginal(id: fileID, type: .image)
            try? storageManager.deleteOriginal(id: fileID, type: .pdf)
            try? storageManager.deleteRedacted(id: fileID, type: .image)
            try? storageManager.deleteRedacted(id: fileID, type: .pdf)
        }
        testFileIDs = []
        super.tearDown()
    }

    // MARK: - 辅助方法

    /// 创建测试数据
    private func createTestData(size: Int = 1024) -> Data {
        var data = Data(count: size)
        data.withUnsafeMutableBytes { ptr in
            arc4random_buf(ptr.baseAddress!, size)
        }
        return data
    }

    // MARK: - 文件保存/加载测试

    /// 测试保存和加载加密的原始图片
    func testSaveAndLoadEncryptedOriginalImage() throws {
        // Given: 测试数据和 ID
        let testData = createTestData()
        let fileID = UUID()
        testFileIDs.append(fileID)

        // When: 保存加密原文件
        let savedURL = try storageManager.saveEncryptedOriginal(data: testData, id: fileID, type: .image)

        // Then: 文件应该存在
        XCTAssertTrue(storageManager.fileExists(at: savedURL), "保存的文件应该存在")

        // And: 应该能加载回来
        let loadedData = try storageManager.loadEncryptedOriginal(id: fileID, type: .image)
        XCTAssertEqual(testData, loadedData, "加载的数据应该与保存的数据相同")
    }

    /// 测试保存和加载加密的原始 PDF
    func testSaveAndLoadEncryptedOriginalPDF() throws {
        // Given: 测试数据
        let testData = createTestData()
        let fileID = UUID()
        testFileIDs.append(fileID)

        // When: 保存加密原文件
        let savedURL = try storageManager.saveEncryptedOriginal(data: testData, id: fileID, type: .pdf)

        // Then: 能正确加载
        let loadedData = try storageManager.loadEncryptedOriginal(id: fileID, type: .pdf)
        XCTAssertEqual(testData, loadedData, "PDF 文件应该能正确保存和加载")
    }

    /// 测试保存和加载缩略图
    func testSaveAndLoadEncryptedThumbnail() throws {
        // Given: 缩略图数据
        let thumbnailData = createTestData(size: 512)
        let fileID = UUID()
        testFileIDs.append(fileID)

        // When: 保存缩略图
        let savedURL = try storageManager.saveEncryptedThumbnail(data: thumbnailData, id: fileID, type: .image)

        // Then: 能正确加载
        XCTAssertTrue(storageManager.fileExists(at: savedURL))
        let loadedData = try storageManager.loadEncryptedThumbnail(id: fileID, type: .image)
        XCTAssertEqual(thumbnailData, loadedData, "缩略图应该能正确保存和加载")
    }

    /// 测试保存和加载脱敏文件
    func testSaveAndLoadRedactedFile() throws {
        // Given: 脱敏文件数据
        let redactedData = createTestData()
        let fileID = UUID()
        testFileIDs.append(fileID)

        // When: 保存脱敏文件
        let savedURL = try storageManager.saveRedactedFile(data: redactedData, id: fileID, type: .image)

        // Then: 能正确加载
        XCTAssertTrue(storageManager.fileExists(at: savedURL))
        let loadedData = try storageManager.loadRedactedFile(id: fileID, type: .image)
        XCTAssertEqual(redactedData, loadedData, "脱敏文件应该能正确保存和加载")
    }

    /// 测试保存脱敏文件的缩略图
    func testSaveRedactedThumbnail() throws {
        // Given: 脱敏缩略图数据
        let thumbnailData = createTestData(size: 256)
        let fileID = UUID()
        testFileIDs.append(fileID)

        // When: 保存脱敏缩略图
        let savedURL = try storageManager.saveRedactedThumbnail(data: thumbnailData, id: fileID, type: .image)

        // Then: 文件应该存在且能读取
        XCTAssertTrue(storageManager.fileExists(at: savedURL), "脱敏缩略图应该被保存")
        let loadedData = try Data(contentsOf: savedURL)
        XCTAssertEqual(thumbnailData, loadedData, "脱敏缩略图数据应该正确")
    }

    /// 测试覆盖已存在的文件
    func testOverwriteExistingFile() throws {
        // Given: 先保存第一个版本
        let firstData = "第一版内容".data(using: .utf8)!
        let fileID = UUID()
        testFileIDs.append(fileID)
        _ = try storageManager.saveEncryptedOriginal(data: firstData, id: fileID, type: .image)

        // When: 保存第二个版本 (覆盖)
        let secondData = "第二版内容".data(using: .utf8)!
        _ = try storageManager.saveEncryptedOriginal(data: secondData, id: fileID, type: .image)

        // Then: 应该读取到第二版的内容
        let loadedData = try storageManager.loadEncryptedOriginal(id: fileID, type: .image)
        XCTAssertEqual(secondData, loadedData, "文件应该被正确覆盖")
        XCTAssertNotEqual(firstData, loadedData, "旧版本不应该存在")
    }

    // MARK: - 文件删除测试

    /// 测试删除原文件
    func testDeleteOriginalFile() throws {
        // Given: 保存的文件
        let testData = createTestData()
        let fileID = UUID()
        let savedURL = try storageManager.saveEncryptedOriginal(data: testData, id: fileID, type: .image)
        XCTAssertTrue(storageManager.fileExists(at: savedURL))

        // When: 删除文件
        try storageManager.deleteOriginal(id: fileID, type: .image)

        // Then: 文件不应该存在
        XCTAssertFalse(storageManager.fileExists(at: savedURL), "删除后文件不应该存在")

        // And: 加载应该失败
        XCTAssertThrowsError(try storageManager.loadEncryptedOriginal(id: fileID, type: .image))
    }

    /// 测试删除原文件和缩略图
    func testDeleteOriginalAndThumbnail() throws {
        // Given: 保存的文件和缩略图
        let fileData = createTestData()
        let thumbnailData = createTestData(size: 256)
        let fileID = UUID()
        testFileIDs.append(fileID)

        let fileURL = try storageManager.saveEncryptedOriginal(data: fileData, id: fileID, type: .image)
        let thumbURL = try storageManager.saveEncryptedThumbnail(data: thumbnailData, id: fileID, type: .image)

        // When: 删除原文件 (应该同时删除缩略图)
        try storageManager.deleteOriginal(id: fileID, type: .image)

        // Then: 两个文件都不应该存在
        XCTAssertFalse(storageManager.fileExists(at: fileURL), "原文件应该被删除")
        XCTAssertFalse(storageManager.fileExists(at: thumbURL), "缩略图应该被删除")
    }

    /// 测试删除脱敏文件
    func testDeleteRedactedFile() throws {
        // Given: 保存的脱敏文件
        let testData = createTestData()
        let fileID = UUID()
        let savedURL = try storageManager.saveRedactedFile(data: testData, id: fileID, type: .pdf)

        // When: 删除文件
        try storageManager.deleteRedacted(id: fileID, type: .pdf)

        // Then: 文件不应该存在
        XCTAssertFalse(storageManager.fileExists(at: savedURL))
    }

    /// 测试删除不存在的文件 (应该不抛出错误)
    func testDeleteNonExistentFile() {
        // Given: 一个不存在的文件 ID
        let nonExistentID = UUID()

        // When & Then: 删除不存在的文件应该成功 (不抛错)
        XCTAssertNoThrow(try storageManager.deleteOriginal(id: nonExistentID, type: .image))
        XCTAssertNoThrow(try storageManager.deleteRedacted(id: nonExistentID, type: .pdf))
    }

    // MARK: - 文件 URL 测试

    /// 测试获取原文件 URL
    func testGetOriginalURL() {
        // Given: 文件 ID
        let fileID = UUID()

        // When: 获取图片和 PDF 的 URL
        let imageURL = storageManager.getOriginalURL(for: fileID, type: .image)
        let pdfURL = storageManager.getOriginalURL(for: fileID, type: .pdf)

        // Then: URL 应该包含正确的路径和扩展名
        XCTAssertTrue(imageURL.path.contains("Images"), "图片 URL 应该在 Images 目录")
        XCTAssertTrue(imageURL.path.contains(fileID.uuidString), "URL 应该包含文件 ID")
        XCTAssertTrue(imageURL.path.hasSuffix(".enc"), "URL 应该有 .enc 扩展名")

        XCTAssertTrue(pdfURL.path.contains("PDFs"), "PDF URL 应该在 PDFs 目录")
    }

    /// 测试获取缩略图 URL
    func testGetThumbnailURL() {
        // Given: 文件 ID
        let fileID = UUID()

        // When: 获取缩略图 URL
        let thumbURL = storageManager.getThumbnailURL(for: fileID, type: .image)

        // Then: URL 应该包含正确的路径
        XCTAssertTrue(thumbURL.path.contains("Thumbnails"))
        XCTAssertTrue(thumbURL.path.contains("_thumb.enc"))
    }

    /// 测试获取脱敏文件 URL
    func testGetRedactedURL() {
        // Given: 文件 ID
        let fileID = UUID()

        // When: 获取脱敏文件 URL
        let imageURL = storageManager.getRedactedURL(for: fileID, type: .image)
        let pdfURL = storageManager.getRedactedURL(for: fileID, type: .pdf)

        // Then: URL 应该有正确的扩展名
        XCTAssertTrue(imageURL.path.hasSuffix(".png"), "图片应该是 .png")
        XCTAssertTrue(pdfURL.path.hasSuffix(".pdf"), "PDF 应该是 .pdf")
    }

    // MARK: - 文件信息测试

    /// 测试获取文件大小
    func testGetFileSize() throws {
        // Given: 已知大小的文件
        let testSize = 2048
        let testData = createTestData(size: testSize)
        let fileID = UUID()
        testFileIDs.append(fileID)

        // When: 保存文件并获取大小
        let savedURL = try storageManager.saveEncryptedOriginal(data: testData, id: fileID, type: .image)
        let fileSize = storageManager.getFileSize(at: savedURL)

        // Then: 文件大小应该匹配
        XCTAssertEqual(Int(fileSize), testSize, "文件大小应该与保存的数据大小相同")
    }

    /// 测试检查文件是否存在
    func testFileExists() throws {
        // Given: 保存一个文件
        let testData = createTestData()
        let fileID = UUID()
        testFileIDs.append(fileID)
        let savedURL = try storageManager.saveEncryptedOriginal(data: testData, id: fileID, type: .image)

        // Then: 应该能检测到文件存在
        XCTAssertTrue(storageManager.fileExists(at: savedURL), "已保存的文件应该存在")

        // When: 删除文件
        try storageManager.deleteOriginal(id: fileID, type: .image)

        // Then: 应该检测到文件不存在
        XCTAssertFalse(storageManager.fileExists(at: savedURL), "已删除的文件不应该存在")
    }

    // MARK: - 存储使用情况测试

    /// 测试获取存储使用情况
    func testGetStorageUsage() throws {
        // Given: 保存一些测试文件
        let fileID1 = UUID()
        let fileID2 = UUID()
        testFileIDs.append(contentsOf: [fileID1, fileID2])

        let testData1 = createTestData(size: 1024)
        let testData2 = createTestData(size: 2048)

        _ = try storageManager.saveEncryptedOriginal(data: testData1, id: fileID1, type: .image)
        _ = try storageManager.saveRedactedFile(data: testData2, id: fileID2, type: .image)

        // When: 获取存储使用情况
        let usage = storageManager.getStorageUsage()

        // Then: 应该统计到文件
        XCTAssertGreaterThan(usage.total, 0, "总存储应该大于 0")
        XCTAssertGreaterThan(usage.originals, 0, "原文件存储应该大于 0")
        XCTAssertGreaterThan(usage.redacted, 0, "脱敏文件存储应该大于 0")
        XCTAssertGreaterThan(usage.fileCount, 0, "文件计数应该大于 0")

        // And: 总大小应该等于各部分之和
        XCTAssertEqual(usage.total, usage.originals + usage.redacted, "总大小应该等于各部分之和")
    }

    /// 测试存储使用情况的格式化字符串
    func testStorageUsageFormattedStrings() throws {
        // Given: 保存一个文件
        let testData = createTestData(size: 1024)
        let fileID = UUID()
        testFileIDs.append(fileID)
        _ = try storageManager.saveEncryptedOriginal(data: testData, id: fileID, type: .image)

        // When: 获取格式化字符串
        let usage = storageManager.getStorageUsage()

        // Then: 格式化字符串应该包含单位
        XCTAssertFalse(usage.formattedTotal.isEmpty, "格式化总大小不应该为空")
        XCTAssertFalse(usage.formattedOriginals.isEmpty, "格式化原文件大小不应该为空")
        XCTAssertTrue(usage.formattedTotal.contains("KB") || usage.formattedTotal.contains("bytes"),
                     "格式化字符串应该包含单位")
    }

    // MARK: - 并发访问测试

    /// 测试并发保存文件
    func testConcurrentFileSaves() async throws {
        // Given: 多个文件需要并发保存
        let fileCount = 10
        let fileIDs = (0..<fileCount).map { _ in UUID() }
        testFileIDs.append(contentsOf: fileIDs)

        // When: 并发保存文件
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, fileID) in fileIDs.enumerated() {
                group.addTask {
                    let testData = "文件\(index)".data(using: .utf8)!
                    _ = try self.storageManager.saveEncryptedOriginal(data: testData, id: fileID, type: .image)
                }
            }
            try await group.waitForAll()
        }

        // Then: 所有文件都应该保存成功
        for (index, fileID) in fileIDs.enumerated() {
            let loadedData = try storageManager.loadEncryptedOriginal(id: fileID, type: .image)
            let expectedData = "文件\(index)".data(using: .utf8)!
            XCTAssertEqual(loadedData, expectedData, "并发保存的文件 \(index) 应该正确")
        }
    }

    /// 测试并发读取文件
    func testConcurrentFileLoads() async throws {
        // Given: 预先保存多个文件
        let fileCount = 5
        let fileIDs = (0..<fileCount).map { _ in UUID() }
        testFileIDs.append(contentsOf: fileIDs)

        for (index, fileID) in fileIDs.enumerated() {
            let testData = "测试文件\(index)".data(using: .utf8)!
            _ = try storageManager.saveEncryptedOriginal(data: testData, id: fileID, type: .image)
        }

        // When: 并发读取所有文件
        let loadedDataArray = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, fileID) in fileIDs.enumerated() {
                group.addTask {
                    let data = try self.storageManager.loadEncryptedOriginal(id: fileID, type: .image)
                    return (index, data)
                }
            }

            var results: [(Int, Data)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }

        // Then: 所有数据都应该正确
        for (index, loadedData) in loadedDataArray {
            let expectedData = "测试文件\(index)".data(using: .utf8)!
            XCTAssertEqual(loadedData, expectedData, "并发读取的文件 \(index) 应该正确")
        }
    }

    /// 测试并发删除文件
    func testConcurrentFileDeletes() async throws {
        // Given: 预先保存多个文件
        let fileIDs = (0..<5).map { _ in UUID() }

        for fileID in fileIDs {
            let testData = createTestData()
            _ = try storageManager.saveEncryptedOriginal(data: testData, id: fileID, type: .image)
        }

        // When: 并发删除所有文件
        try await withThrowingTaskGroup(of: Void.self) { group in
            for fileID in fileIDs {
                group.addTask {
                    try self.storageManager.deleteOriginal(id: fileID, type: .image)
                }
            }
            try await group.waitForAll()
        }

        // Then: 所有文件都应该被删除
        for fileID in fileIDs {
            let url = storageManager.getOriginalURL(for: fileID, type: .image)
            XCTAssertFalse(storageManager.fileExists(at: url), "文件应该被删除")
        }
    }

    // MARK: - 边界情况测试

    /// 测试保存空数据
    func testSaveEmptyData() throws {
        // Given: 空数据
        let emptyData = Data()
        let fileID = UUID()
        testFileIDs.append(fileID)

        // When: 保存空数据
        let savedURL = try storageManager.saveEncryptedOriginal(data: emptyData, id: fileID, type: .image)

        // Then: 应该能保存和加载空数据
        XCTAssertTrue(storageManager.fileExists(at: savedURL))
        let loadedData = try storageManager.loadEncryptedOriginal(id: fileID, type: .image)
        XCTAssertEqual(emptyData, loadedData, "空数据应该能正确保存和加载")
    }

    /// 测试加载不存在的文件
    func testLoadNonExistentFile() {
        // Given: 一个不存在的文件 ID
        let nonExistentID = UUID()

        // When & Then: 加载应该失败
        XCTAssertThrowsError(try storageManager.loadEncryptedOriginal(id: nonExistentID, type: .image)) { error in
            // 验证错误类型 (应该是文件不存在错误)
            XCTAssertTrue(error is CocoaError, "应该抛出 Cocoa 文件错误")
        }
    }
}
