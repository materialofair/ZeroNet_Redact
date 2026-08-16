//
//  ImportManager.swift
//  ZeroNet Redact
//
//  导入管理器 - 统一管理文件导入流程
//

import CoreData
import CryptoKit
import Foundation
import PDFKit
import UIKit

/// 导入重复结果
enum ImportDuplicateResult {
    case success(RedactableFile)
    case duplicate(existingFile: OriginalFile)
}

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

    /// 导入文件（检测重复）
    /// - Parameter sources: 导入源数组
    /// - Returns: 导入的文件数组
    func importFiles(from sources: [ImportSource]) async throws -> [RedactableFile] {
        var importedFiles: [RedactableFile] = []

        for source in sources {
            let file = try await processImport(source)
            importedFiles.append(file)
        }

        // 保存Core Data上下文；失败则回滚并清理本批已写入的磁盘文件
        do {
            try context.save()
        } catch {
            context.rollback()
            for file in importedFiles {
                try? storage.deleteOriginal(id: file.id, type: file.fileType)
            }
            throw error
        }

        return importedFiles
    }

    /// 导入单个文件
    /// - Parameter source: 导入源
    /// - Returns: 导入的文件
    func importFile(from source: ImportSource) async throws -> RedactableFile {
        let file = try await processImport(source)
        do {
            try context.save()
        } catch {
            context.rollback()
            try? storage.deleteOriginal(id: file.id, type: file.fileType)
            throw error
        }
        return file
    }

    /// 导入文件并检测重复
    /// - Parameter source: 导入源
    /// - Returns: 导入结果（成功或重复）
    func importFileWithDuplicateCheck(from source: ImportSource) async throws
        -> ImportDuplicateResult
    {
        let result = try await processImportWithDuplicateCheck(source)
        if case .success(let file) = result {
            do {
                try context.save()
            } catch {
                context.rollback()
                try? storage.deleteOriginal(id: file.id, type: file.fileType)
                throw error
            }
        }
        return result
    }

    // MARK: - 内部处理逻辑

    /// 计算数据的SHA256哈希值
    static func hash(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 检查文件是否已存在
    private func checkDuplicate(hash: String) -> OriginalFile? {
        let request: NSFetchRequest<OriginalFile> = OriginalFile.fetchRequest()
        request.predicate = NSPredicate(format: "contentHash == %@", hash)
        request.fetchLimit = 1

        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("❌ 检查重复文件失败: \(error)")
            return nil
        }
    }

    /// 处理导入并检测重复
    private func processImportWithDuplicateCheck(_ source: ImportSource) async throws
        -> ImportDuplicateResult
    {
        // 1. 检测文件类型
        let fileType = detectFileType(from: source)

        // 2. 根据类型选择处理器
        let processor: FileImportProcessor
        switch fileType {
        case .image:
            processor = ImageImportProcessor()
        case .pdf:
            processor = PDFImportProcessor()
        case .video:
            throw ImportError.unsupportedSource
        }

        // 3-6. 加载数据、哈希、元数据、缩略图：全部后台执行（大文件读取与解码不阻塞主线程）
        let prepared: (data: Data, contentHash: String, metadata: [String: Any], thumbnailData: Data) =
            try await Task.detached(priority: .userInitiated) {
                let data = try await processor.loadData(from: source)
                let contentHash = ImportManager.hash(of: data)
                let metadata = processor.extractMetadata(from: data)
                let thumbnailData = try await processor.generateThumbnail(from: data)
                return (data, contentHash, metadata, thumbnailData)
            }.value
        let data = prepared.data
        let contentHash = prepared.contentHash
        let metadata = prepared.metadata
        let thumbnailData = prepared.thumbnailData

        // 检查重复（主线程 Core Data）
        if let existingFile = checkDuplicate(hash: contentHash) {
            print("⚠️ ImportManager: 检测到重复文件，哈希值=\(contentHash)")
            return .duplicate(existingFile: existingFile)
        }

        // 7. 加密（后台，CPU 密集）
        let encrypted: (original: Data, thumbnail: Data) =
            try await Task.detached(priority: .userInitiated) {
                let encryptedData = try CryptoEngine.shared.encrypt(data: data)
                let encryptedThumbnail = try CryptoEngine.shared.encrypt(data: thumbnailData)
                return (encryptedData, encryptedThumbnail)
            }.value
        let encryptedData = encrypted.original
        let encryptedThumbnail = encrypted.thumbnail

        // 8. 保存到文件系统（任一步失败都清理已写入的文件，避免孤儿加密文件）
        let fileId = UUID()
        print("💾 ImportManager: 保存文件 ID=\(fileId)")

        let dataURL = try storage.saveEncryptedOriginal(
            data: encryptedData,
            id: fileId,
            type: fileType
        )
        print("✅ 原文件已保存: \(dataURL.path)")

        let thumbnailURL: URL
        do {
            thumbnailURL = try storage.saveEncryptedThumbnail(
                data: encryptedThumbnail,
                id: fileId,
                type: fileType
            )
            print("✅ 缩略图已保存: \(thumbnailURL.path)")
        } catch {
            try? storage.deleteOriginal(id: fileId, type: fileType)
            throw error
        }

        // 9. 创建Core Data实体（失败则清理磁盘文件）
        do {
            return .success(
                try createFileEntity(
                    id: fileId,
                    type: fileType,
                    dataPath: dataURL.path,
                    thumbnailPath: thumbnailURL.path,
                    fileSize: Int64(data.count),
                    metadata: metadata,
                    contentHash: contentHash
                ))
        } catch {
            try? storage.deleteOriginal(id: fileId, type: fileType)
            throw error
        }
    }

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
        case .video:
            throw ImportError.unsupportedSource
        }

        // 3-6. 加载数据、元数据、缩略图：全部后台执行（大文件读取与解码不阻塞主线程）
        let prepared: (data: Data, metadata: [String: Any], thumbnailData: Data) =
            try await Task.detached(priority: .userInitiated) {
                let data = try await processor.loadData(from: source)
                let metadata = processor.extractMetadata(from: data)
                let thumbnailData = try await processor.generateThumbnail(from: data)
                return (data, metadata, thumbnailData)
            }.value
        let data = prepared.data
        let metadata = prepared.metadata
        let thumbnailData = prepared.thumbnailData

        // 6. 加密（后台，CPU 密集）
        let encrypted: (original: Data, thumbnail: Data) =
            try await Task.detached(priority: .userInitiated) {
                let encryptedData = try CryptoEngine.shared.encrypt(data: data)
                let encryptedThumbnail = try CryptoEngine.shared.encrypt(data: thumbnailData)
                return (encryptedData, encryptedThumbnail)
            }.value
        let encryptedData = encrypted.original
        let encryptedThumbnail = encrypted.thumbnail

        // 7. 保存到文件系统（任一步失败都清理已写入的文件，避免孤儿加密文件）
        let fileId = UUID()
        print("💾 ImportManager: 保存文件 ID=\(fileId)")

        let dataURL = try storage.saveEncryptedOriginal(
            data: encryptedData,
            id: fileId,
            type: fileType
        )
        print("✅ 原文件已保存: \(dataURL.path)")

        let thumbnailURL: URL
        do {
            thumbnailURL = try storage.saveEncryptedThumbnail(
                data: encryptedThumbnail,
                id: fileId,
                type: fileType
            )
            print("✅ 缩略图已保存: \(thumbnailURL.path)")
        } catch {
            try? storage.deleteOriginal(id: fileId, type: fileType)
            throw error
        }

        // 8. 创建Core Data实体（失败则清理磁盘文件）
        do {
            return try createFileEntity(
                id: fileId,
                type: fileType,
                dataPath: dataURL.path,
                thumbnailPath: thumbnailURL.path,
                fileSize: Int64(data.count),
                metadata: metadata
            )
        } catch {
            try? storage.deleteOriginal(id: fileId, type: fileType)
            throw error
        }
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
        metadata: [String: Any],
        contentHash: String? = nil
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
                orientation: orientation,
                contentHash: contentHash
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
                isEncrypted: isEncrypted,
                contentHash: contentHash
            )
        case .video:
            throw ImportError.unsupportedSource
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

            // 保存Core Data；失败则回滚并清理本批已写入的磁盘文件
            do {
                try self.context.save()
            } catch {
                self.context.rollback()
                for file in files.compactMap({ $0 }) {
                    try? self.storage.deleteOriginal(id: file.id, type: file.fileType)
                }
                throw error
            }

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

        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data加载失败: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
