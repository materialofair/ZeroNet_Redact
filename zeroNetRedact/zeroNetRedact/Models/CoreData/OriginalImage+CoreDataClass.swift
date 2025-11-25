//
//  OriginalImage+CoreDataClass.swift
//  ZeroNet Redact
//
//  图片文件Core Data实体类
//

import CoreData
import Foundation
import UIKit

@objc(OriginalImage)
public class OriginalImage: OriginalFile {

    // MARK: - Image Specific Properties

    /// 图片方向
    var orientation: UIImage.Orientation {
        UIImage.Orientation(rawValue: Int(orientationRaw)) ?? .up
    }

    /// 图片尺寸
    var size: CGSize {
        return CGSize(width: Int(width), height: Int(height))
    }

    /// 宽高比
    var aspectRatio: CGFloat {
        guard height > 0 else { return 1.0 }
        return CGFloat(width) / CGFloat(height)
    }

    // MARK: - Helper Methods

    /// 创建图片文件
    static func create(
        in context: NSManagedObjectContext,
        id: UUID,
        encryptedDataPath: String,
        encryptedThumbnailPath: String,
        fileSize: Int64,
        width: Int,
        height: Int,
        orientation: UIImage.Orientation
    ) -> OriginalImage {
        let image = OriginalImage(context: context)
        image.id = id
        image.fileType = .image
        image.encryptedDataPath = encryptedDataPath
        image.encryptedThumbnailPath = encryptedThumbnailPath
        image.createdAt = Date()
        image.fileSize = fileSize
        image.width = Int64(width)
        image.height = Int64(height)
        image.orientationRaw = Int64(orientation.rawValue)

        return image
    }
}
