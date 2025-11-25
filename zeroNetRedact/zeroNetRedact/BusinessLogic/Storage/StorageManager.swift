//
//  StorageManager.swift
//  ZeroNet Redact
//
//  存储管理器 - 管理文件系统布局和文件操作
//

import Foundation

/// 存储管理器单例
class StorageManager {
    static let shared = StorageManager()

    // MARK: - 目录URL

    private let baseURL: URL
    private let originalsURL: URL
    private let thumbnailsURL: URL
    private let redactedURL: URL

    private init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        baseURL = documentsURL
        originalsURL = documentsURL.appendingPathComponent("Originals")
        thumbnailsURL = documentsURL.appendingPathComponent("Thumbnails")
        redactedURL = documentsURL.appendingPathComponent("Redacted")

        createDirectoryStructure()
    }

    // MARK: - 目录结构创建

    private func createDirectoryStructure() {
        let directories = [
            originalsURL.appendingPathComponent("Images"),
            originalsURL.appendingPathComponent("PDFs"),
            thumbnailsURL.appendingPathComponent("Images"),
            thumbnailsURL.appendingPathComponent("PDFs"),
            redactedURL.appendingPathComponent("Images"),
            redactedURL.appendingPathComponent("PDFs"),
        ]

        for directory in directories {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    // MARK: - 保存文件

    /// 保存加密的原文件
    func saveEncryptedOriginal(data: Data, id: UUID, type: FileType) throws -> URL {
        let subdir = type == .image ? "Images" : "PDFs"
        let url =
            originalsURL
            .appendingPathComponent(subdir)
            .appendingPathComponent("\(id.uuidString).enc")

        try data.write(to: url, options: .atomicWrite)
        return url
    }

    /// 保存加密的缩略图
    func saveEncryptedThumbnail(data: Data, id: UUID, type: FileType) throws -> URL {
        let subdir = type == .image ? "Images" : "PDFs"
        let url =
            thumbnailsURL
            .appendingPathComponent(subdir)
            .appendingPathComponent("\(id.uuidString)_thumb.enc")

        try data.write(to: url, options: .atomicWrite)
        return url
    }

    /// 保存脱敏文件（明文）
    func saveRedactedFile(data: Data, id: UUID, type: FileType) throws -> URL {
        let subdir: String
        let ext: String

        switch type {
        case .image:
            subdir = "Images"
            ext = "png"
        case .pdf:
            subdir = "PDFs"
            ext = "pdf"
        }

        let url =
            redactedURL
            .appendingPathComponent(subdir)
            .appendingPathComponent("\(id.uuidString).\(ext)")

        print("💾 [saveRedactedFile] 保存路径: \(url.path)")
        print("💾 数据大小: \(data.count) bytes")

        // 确保目录存在
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            print("💾 创建目录: \(directory.path)")
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        try data.write(to: url, options: .atomicWrite)

        // 验证文件已保存
        if FileManager.default.fileExists(atPath: url.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int64) ?? 0
            print("✅ [saveRedactedFile] 文件已保存，磁盘大小: \(size) bytes")
        } else {
            print("❌ [saveRedactedFile] 文件保存失败！")
        }

        return url
    }

    /// 保存脱敏文件的缩略图（明文）
    func saveRedactedThumbnail(data: Data, id: UUID, type: FileType) throws -> URL {
        let subdir = type == .image ? "Images" : "PDFs"
        let url =
            redactedURL
            .appendingPathComponent(subdir)
            .appendingPathComponent("\(id.uuidString)_thumb.png")

        print("💾 [saveRedactedThumbnail] 保存路径: \(url.path)")
        print("💾 缩略图数据大小: \(data.count) bytes")

        // 确保目录存在
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            print("💾 创建目录: \(directory.path)")
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        try data.write(to: url, options: .atomicWrite)

        // 验证文件已保存
        if FileManager.default.fileExists(atPath: url.path) {
            print("✅ [saveRedactedThumbnail] 缩略图已保存")
        } else {
            print("❌ [saveRedactedThumbnail] 缩略图保存失败！")
        }

        return url
    }

    // MARK: - 读取文件

    /// 读取加密的原文件
    func loadEncryptedOriginal(id: UUID, type: FileType) throws -> Data {
        let url = getOriginalURL(for: id, type: type)
        return try Data(contentsOf: url)
    }

    /// 读取加密的缩略图
    func loadEncryptedThumbnail(id: UUID, type: FileType) throws -> Data {
        let url = getThumbnailURL(for: id, type: type)
        return try Data(contentsOf: url)
    }

    /// 读取脱敏文件
    func loadRedactedFile(id: UUID, type: FileType) throws -> Data {
        let url = getRedactedURL(for: id, type: type)
        return try Data(contentsOf: url)
    }

    // MARK: - 获取文件URL

    func getOriginalURL(for id: UUID, type: FileType) -> URL {
        let subdir = type == .image ? "Images" : "PDFs"
        return
            originalsURL
            .appendingPathComponent(subdir)
            .appendingPathComponent("\(id.uuidString).enc")
    }

    func getThumbnailURL(for id: UUID, type: FileType) -> URL {
        let subdir = type == .image ? "Images" : "PDFs"
        return
            thumbnailsURL
            .appendingPathComponent(subdir)
            .appendingPathComponent("\(id.uuidString)_thumb.enc")
    }

    func getRedactedURL(for id: UUID, type: FileType) -> URL {
        let subdir = type == .image ? "Images" : "PDFs"
        let ext = type == .image ? "png" : "pdf"
        return
            redactedURL
            .appendingPathComponent(subdir)
            .appendingPathComponent("\(id.uuidString).\(ext)")
    }

    // MARK: - 删除文件

    /// 删除原文件及其缩略图
    func deleteOriginal(id: UUID, type: FileType) throws {
        let originalURL = getOriginalURL(for: id, type: type)
        let thumbnailURL = getThumbnailURL(for: id, type: type)

        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: thumbnailURL)
    }

    /// 删除脱敏文件
    func deleteRedacted(id: UUID, type: FileType) throws {
        let url = getRedactedURL(for: id, type: type)
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - 文件信息

    /// 获取文件大小
    func getFileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int64
        else {
            return 0
        }
        return size
    }

    /// 检查文件是否存在
    func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - 清理

    /// 清理所有临时文件
    func cleanupTempFiles() {
        let tempURL = FileManager.default.temporaryDirectory
        try? FileManager.default.removeItem(at: tempURL)
    }

    /// 获取存储使用情况
    func getStorageUsage() -> StorageUsage {
        var totalSize: Int64 = 0
        var originalsSize: Int64 = 0
        var redactedSize: Int64 = 0
        var fileCount = 0

        // 计算原文件大小
        if let enumerator = FileManager.default.enumerator(
            at: originalsURL, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [
                    .fileSizeKey, .isRegularFileKey,
                ]),
                    let isRegularFile = resourceValues.isRegularFile, isRegularFile,
                    let size = resourceValues.fileSize
                {
                    originalsSize += Int64(size)
                    fileCount += 1
                }
            }
        }

        // 计算脱敏文件大小
        if let enumerator = FileManager.default.enumerator(
            at: redactedURL, includingPropertiesForKeys: [.fileSizeKey])
        {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    redactedSize += Int64(size)
                }
            }
        }

        totalSize = originalsSize + redactedSize

        return StorageUsage(
            total: totalSize,
            originals: originalsSize,
            redacted: redactedSize,
            fileCount: fileCount
        )
    }

    /// 删除文件
    func deleteFile(id: UUID, type: FileType) throws {
        let typeDir = type == .image ? "Images" : "PDFs"
        let originalURL = originalsURL.appendingPathComponent(typeDir).appendingPathComponent(
            "\(id.uuidString).encrypted")
        let thumbnailURL = thumbnailsURL.appendingPathComponent(typeDir).appendingPathComponent(
            "\(id.uuidString).jpg")

        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: thumbnailURL)
    }
}

// MARK: - 存储使用情况

struct StorageUsage {
    let total: Int64
    let originals: Int64
    let redacted: Int64
    let fileCount: Int

    var totalSize: Int64 { total }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var formattedOriginals: String {
        ByteCountFormatter.string(fromByteCount: originals, countStyle: .file)
    }

    var formattedRedacted: String {
        ByteCountFormatter.string(fromByteCount: redacted, countStyle: .file)
    }
}
