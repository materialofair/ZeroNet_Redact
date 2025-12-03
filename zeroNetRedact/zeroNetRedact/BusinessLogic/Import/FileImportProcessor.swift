//
//  FileImportProcessor.swift
//  ZeroNet Redact
//
//  文件导入处理器协议及实现
//

import Foundation
import PDFKit
import Photos
import UIKit

/// 文件导入处理器协议
protocol FileImportProcessor {
    /// 加载数据
    func loadData(from source: ImportSource) async throws -> Data

    /// 生成缩略图
    func generateThumbnail(from data: Data) async throws -> Data

    /// 提取元数据
    func extractMetadata(from data: Data) -> [String: Any]
}

/// 导入源枚举
enum ImportSource {
    case photo(PHAsset)  // 相册照片
    case fileURL(URL)  // 文件URL
    case imageData(Data)  // 图片数据
    case pdfData(Data)  // PDF数据
}

// MARK: - 图片导入处理器

class ImageImportProcessor: FileImportProcessor {

    func loadData(from source: ImportSource) async throws -> Data {
        switch source {
        case .photo(let asset):
            return try await loadFromPhotoAsset(asset)

        case .fileURL(let url):
            // 获取安全作用域资源访问权限
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ ImageImportProcessor: 无法获取文件访问权限")
                throw ImportError.unsupportedSource
            }

            defer {
                url.stopAccessingSecurityScopedResource()
                print("🔒 ImageImportProcessor: 已释放文件访问权限")
            }

            print("🔓 ImageImportProcessor: 已获取文件访问权限，开始读取图片数据")
            let data = try Data(contentsOf: url)
            print("✅ ImageImportProcessor: 图片数据读取成功，大小: \(data.count) bytes")
            return data

        case .imageData(let data):
            return data

        default:
            throw ImportError.unsupportedSource
        }
    }

    func generateThumbnail(from data: Data) async throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImportError.invalidImageData
        }

        let thumbnailSize = CGSize(width: 200, height: 200)
        let thumbnail = image.resized(to: thumbnailSize)

        guard let thumbnailData = thumbnail.pngData() else {
            throw ImportError.thumbnailGenerationFailed
        }

        return thumbnailData
    }

    func extractMetadata(from data: Data) -> [String: Any] {
        guard let image = UIImage(data: data) else {
            return [:]
        }

        return [
            "width": Int(image.size.width),
            "height": Int(image.size.height),
            "orientation": image.imageOrientation.rawValue,
        ]
    }

    // MARK: - Private Methods

    private func loadFromPhotoAsset(_ asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) {
                data, _, _, _ in
                if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ImportError.photoLoadFailed)
                }
            }
        }
    }
}

// MARK: - PDF导入处理器

class PDFImportProcessor: FileImportProcessor {

    func loadData(from source: ImportSource) async throws -> Data {
        switch source {
        case .fileURL(let url):
            // 获取安全作用域资源访问权限
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ PDFImportProcessor: 无法获取文件访问权限")
                throw ImportError.unsupportedSource
            }

            defer {
                url.stopAccessingSecurityScopedResource()
                print("🔒 PDFImportProcessor: 已释放文件访问权限")
            }

            print("🔓 PDFImportProcessor: 已获取文件访问权限，开始读取PDF数据")
            let data = try Data(contentsOf: url)
            print("✅ PDFImportProcessor: PDF数据读取成功，大小: \(data.count) bytes")
            return data

        case .pdfData(let data):
            return data

        default:
            throw ImportError.unsupportedSource
        }
    }

    func generateThumbnail(from data: Data) async throws -> Data {
        guard let document = PDFDocument(data: data),
            let firstPage = document.page(at: 0)
        else {
            throw ImportError.invalidPDFData
        }

        let thumbnailSize = CGSize(width: 200, height: 200)
        let thumbnail = firstPage.thumbnail(of: thumbnailSize, for: .mediaBox)

        guard let thumbnailData = thumbnail.pngData() else {
            throw ImportError.thumbnailGenerationFailed
        }

        return thumbnailData
    }

    func extractMetadata(from data: Data) -> [String: Any] {
        guard let document = PDFDocument(data: data) else {
            return [:]
        }

        var metadata: [String: Any] = [
            "pageCount": document.pageCount
        ]

        // 提取文档属性
        if let attributes = document.documentAttributes {
            if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String {
                metadata["title"] = title
            }
            if let author = attributes[PDFDocumentAttribute.authorAttribute] as? String {
                metadata["author"] = author
            }
            if let creator = attributes[PDFDocumentAttribute.creatorAttribute] as? String {
                metadata["creator"] = creator
            }
        }

        metadata["isEncrypted"] = document.isEncrypted

        return metadata
    }
}

// MARK: - UIImage扩展（缩略图生成）

extension UIImage {
    /// 调整图片大小（保持宽高比）
    func resized(to targetSize: CGSize) -> UIImage {
        let size = self.size

        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height

        let scaleFactor = min(widthRatio, heightRatio)
        let scaledSize = CGSize(
            width: size.width * scaleFactor,
            height: size.height * scaleFactor
        )

        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: scaledSize))
        }
    }
}

// MARK: - 导入错误定义

enum ImportError: LocalizedError {
    case unsupportedSource
    case invalidImageData
    case invalidPDFData
    case photoLoadFailed
    case thumbnailGenerationFailed
    case encryptionFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return NSLocalizedString("import.error.unsupportedSource", comment: "")
        case .invalidImageData:
            return NSLocalizedString("import.error.invalidImageData", comment: "")
        case .invalidPDFData:
            return NSLocalizedString("import.error.invalidPDFData", comment: "")
        case .photoLoadFailed:
            return NSLocalizedString("import.error.photoLoadFailed", comment: "")
        case .thumbnailGenerationFailed:
            return NSLocalizedString("import.error.thumbnailFailed", comment: "")
        case .encryptionFailed:
            return NSLocalizedString("crypto.error.encryptionFailed", comment: "")
        case .saveFailed:
            return NSLocalizedString("import.error.saveFailed", comment: "")
        }
    }
}
