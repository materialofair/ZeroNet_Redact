//
//  OriginalPDF+CoreDataClass.swift
//  ZeroNet Redact
//
//  PDF文件Core Data实体类
//

import CoreData
import Foundation
import PDFKit

@objc(OriginalPDF)
public class OriginalPDF: OriginalFile {

    // MARK: - PDF Specific Properties
    // Properties are now managed as NSManaged attributes in Core Data

    // MARK: - Helper Methods

    /// 创建PDF文件
    static func create(
        in context: NSManagedObjectContext,
        id: UUID,
        encryptedDataPath: String,
        encryptedThumbnailPath: String,
        fileSize: Int64,
        pageCount: Int,
        title: String,
        author: String,
        creator: String,
        isEncrypted: Bool
    ) -> OriginalPDF {
        let pdf = OriginalPDF(context: context)
        pdf.id = id
        pdf.fileType = .pdf
        pdf.encryptedDataPath = encryptedDataPath
        pdf.encryptedThumbnailPath = encryptedThumbnailPath
        pdf.createdAt = Date()
        pdf.fileSize = fileSize
        pdf.pageCount = Int64(pageCount)
        pdf.title = title
        pdf.author = author
        pdf.creator = creator
        pdf.isEncrypted = isEncrypted

        return pdf
    }
}
