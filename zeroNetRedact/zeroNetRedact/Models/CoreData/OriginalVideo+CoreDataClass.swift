import CoreData
import Foundation

@objc(OriginalVideo)
public class OriginalVideo: OriginalFile {
    static func create(
        in context: NSManagedObjectContext,
        id: UUID,
        encryptedDataPath: String,
        encryptedThumbnailPath: String,
        fileSize: Int64,
        duration: Double,
        width: Int64,
        height: Int64,
        nominalFrameRate: Double,
        hasAudio: Bool,
        contentHash: String
    ) -> OriginalVideo {
        let video = OriginalVideo(context: context)
        video.id = id
        video.fileType = .video
        video.encryptedDataPath = encryptedDataPath
        video.encryptedThumbnailPath = encryptedThumbnailPath
        video.createdAt = Date()
        video.fileSize = fileSize
        video.duration = duration
        video.width = width
        video.height = height
        video.nominalFrameRate = nominalFrameRate
        video.hasAudio = hasAudio
        video.contentHash = contentHash
        return video
    }
}
