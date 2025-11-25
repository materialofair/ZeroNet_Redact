//
//  ImportManager.swift
//  ZeroNet Redact
//
//  导入管理器 - 统一管理文件导入流程
//

import CoreData
import Foundation
import PDFKit
import UIKit

/// 导入管理器单例
class ImportManager {
    static let shared = ImportManager()

    private let context: NSManagedObjectContext
    private let crypto = CryptoEngine.shared
    private let storage = StorageManager.shared

    private init() {
        // 使用主上下文（实际项目中应从App获取）
        self.context = PersistenceController.shared.container.viewContext
    }

    // MARK: - 统一导入接口

    /// 导入文件
    /// - Parameter sources: 导入源数组
    /// - Returns: 导入的文件数组
    func importFiles(from sources: [ImportSource]) async throws -> [RedactableFile] {
        var importedFiles: [RedactableFile] = []

        for source in sources {
            let file = try await processImport(source)
            importedFiles.append(file)
        }

        // 保存Core Data上下文
        try context.save()

        return importedFiles
    }

    /// 导入单个文件
    /// - Parameter source: 导入源
    /// - Returns: 导入的文件
    func importFile(from source: ImportSource) async throws -> RedactableFile {
        let file = try await processImport(source)
        try context.save()
        return file
    }

    // MARK: - 内部处理逻辑

    private func processImport(_ source: ImportSource) async throws -> RedactableFile {
        // 1. 检测文件类型
        let fileType = detectFileType(from: source)

        // 2. 根据类型选择处理器
        let processor: FileImportProcessor
        switch fileType {
        case .image:
            processor = ImageImportProcessor()
        case .pdf:
            processor = PDFImportProcessor()
        }

        // 3. 加载原始数据
        let data = try await processor.loadData(from: source)

        // 4. 提取元数据
        let metadata = processor.extractMetadata(from: data)

        // 5. 生成缩略图
        let thumbnailData = try await processor.generateThumbnail(from: data)

        // 6. 加密数据
        let encryptedData = try crypto.encrypt(data: data)
        let encryptedThumbnail = try crypto.encrypt(data: thumbnailData)

        // 7. 保存到文件系统
        let fileId = UUID()
        print("💾 ImportManager: 保存文件 ID=\(fileId)")

        let dataURL = try storage.saveEncryptedOriginal(
            data: encryptedData,
            id: fileId,
            type: fileType
        )
        print("✅ 原文件已保存: \(dataURL.path)")

        let thumbnailURL = try storage.saveEncryptedThumbnail(
            data: encryptedThumbnail,
            id: fileId,
            type: fileType
        )
        print("✅ 缩略图已保存: \(thumbnailURL.path)")

        // 8. 创建Core Data实体
        let file = try createFileEntity(
            id: fileId,
            type: fileType,
            dataPath: dataURL.path,
            thumbnailPath: thumbnailURL.path,
            fileSize: Int64(data.count),
            metadata: metadata
        )

        return file
    }

    // MARK: - 文件类型检测

    private func detectFileType(from source: ImportSource) -> FileType {
        switch source {
        case .photo, .imageData:
            return .image

        case .pdfData:
            return .pdf

        case .fileURL(let url):
            let ext = url.pathExtension.lowercased()
            if ["pdf"].contains(ext) {
                return .pdf
            } else {
                return .image
            }
        }
    }

    // MARK: - Core Data实体创建

    private func createFileEntity(
        id: UUID,
        type: FileType,
        dataPath: String,
        thumbnailPath: String,
        fileSize: Int64,
        metadata: [String: Any]
    ) throws -> RedactableFile {

        switch type {
        case .image:
            let width = metadata["width"] as? Int ?? 0
            let height = metadata["height"] as? Int ?? 0
            let orientationRaw = metadata["orientation"] as? Int ?? 0
            let orientation = UIImage.Orientation(rawValue: orientationRaw) ?? .up

            return OriginalImage.create(
                in: context,
                id: id,
                encryptedDataPath: dataPath,
                encryptedThumbnailPath: thumbnailPath,
                fileSize: fileSize,
                width: width,
                height: height,
                orientation: orientation
            )

        case .pdf:
            let pageCount = metadata["pageCount"] as? Int ?? 0
            let title = metadata["title"] as? String ?? ""
            let author = metadata["author"] as? String ?? ""
            let creator = metadata["creator"] as? String ?? ""
            let isEncrypted = metadata["isEncrypted"] as? Bool ?? false

            return OriginalPDF.create(
                in: context,
                id: id,
                encryptedDataPath: dataPath,
                encryptedThumbnailPath: thumbnailPath,
                fileSize: fileSize,
                pageCount: pageCount,
                title: title,
                author: author,
                creator: creator,
                isEncrypted: isEncrypted
            )
        }
    }

    // MARK: - 批量导入

    /// 批量导入文件（并发）
    /// - Parameter sources: 导入源数组
    /// - Returns: 导入的文件数组
    func batchImport(from sources: [ImportSource]) async throws -> [RedactableFile] {
        // 使用TaskGroup并发导入
        return try await withThrowingTaskGroup(of: (Int, RedactableFile).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    let file = try await self.processImport(source)
                    return (index, file)
                }
            }

            var files: [RedactableFile?] = Array(repeating: nil, count: sources.count)
            for try await (index, file) in group {
                files[index] = file
            }

            // 保存Core Data
            try self.context.save()

            return files.compactMap { $0 }
        }
    }
}

// MARK: - Persistence Controller

/// Core Data持久化控制器（简化版）
class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "ZeroNetRedact")

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data加载失败: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
