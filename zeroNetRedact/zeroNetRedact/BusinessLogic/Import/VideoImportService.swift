import AVFoundation
import CoreData
import Foundation
import UIKit

@MainActor
final class VideoImportService {
    static let shared = VideoImportService()

    private let context = PersistenceController.shared.container.viewContext

    private init() {}

    func importVideo(from sourceURL: URL, group: FileGroup?) async throws -> OriginalVideo {
        let workspace = try StorageManager.shared.createVideoWorkspace()
        defer { StorageManager.shared.removeVideoWorkspace(workspace) }

        let sourceExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let localSource = workspace.appendingPathComponent("source").appendingPathExtension(sourceExtension)
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            if sourceURL.deletingLastPathComponent().standardizedFileURL
                == FileManager.default.temporaryDirectory.standardizedFileURL,
                sourceURL.lastPathComponent.hasPrefix("video-import-")
            {
                try? FileManager.default.removeItem(at: sourceURL)
            }
        }
        try FileManager.default.copyItem(at: sourceURL, to: localSource)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: localSource.path
        )

        let metadata = try await Self.loadMetadata(from: localSource)
        let thumbnailData = try VideoThumbnailGenerator.jpegData(from: localSource)
        let encryptedStagingURL = workspace.appendingPathComponent("original.enc")

        let encryptionResult = try await Task.detached(priority: .userInitiated) {
            try ChunkedFileCipher.shared.encrypt(
                sourceURL: localSource,
                destinationURL: encryptedStagingURL,
                shouldCancel: { Task.isCancelled }
            )
        }.value

        let duplicateRequest: NSFetchRequest<OriginalFile> = OriginalFile.fetchRequest()
        duplicateRequest.predicate = NSPredicate(format: "contentHash == %@", encryptionResult.sha256)
        duplicateRequest.fetchLimit = 1
        if try context.count(for: duplicateRequest) > 0 {
            throw VideoProcessingError.duplicate
        }

        let id = UUID()
        let encryptedThumbnail = try CryptoEngine.shared.encrypt(data: thumbnailData)
        var committedOriginalURL: URL?
        var committedThumbnailURL: URL?
        var insertedVideo: OriginalVideo?
        do {
            committedOriginalURL = try StorageManager.shared.commitEncryptedOriginal(
                from: encryptedStagingURL,
                id: id,
                type: .video
            )
            committedThumbnailURL = try StorageManager.shared.saveEncryptedThumbnail(
                data: encryptedThumbnail,
                id: id,
                type: .video
            )

            let video = OriginalVideo.create(
                in: context,
                id: id,
                encryptedDataPath: committedOriginalURL?.path ?? "",
                encryptedThumbnailPath: committedThumbnailURL?.path ?? "",
                fileSize: encryptionResult.plaintextSize,
                duration: metadata.duration,
                width: metadata.width,
                height: metadata.height,
                nominalFrameRate: metadata.nominalFrameRate,
                hasAudio: metadata.hasAudio,
                contentHash: encryptionResult.sha256
            )
            insertedVideo = video
            video.group = group ?? GroupManager.shared.getDefaultGroup()
            try context.save()
            return video
        } catch {
            if let insertedVideo, insertedVideo.managedObjectContext != nil {
                context.delete(insertedVideo)
            }
            if let committedOriginalURL { try? FileManager.default.removeItem(at: committedOriginalURL) }
            if let committedThumbnailURL { try? FileManager.default.removeItem(at: committedThumbnailURL) }
            throw error
        }
    }

    static func decryptVideo(_ video: OriginalVideo, into workspace: URL) async throws -> URL {
        let encryptedURL = StorageManager.shared.getOriginalURL(for: video.id, type: .video)
        let destination = workspace.appendingPathComponent("source.mov")
        return try await Task.detached(priority: .userInitiated) {
            try ChunkedFileCipher.shared.decrypt(
                sourceURL: encryptedURL,
                destinationURL: destination,
                shouldCancel: { Task.isCancelled }
            )
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: destination.path
            )
            return destination
        }.value
    }

    private static func loadMetadata(from url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { throw VideoProcessingError.invalidDuration }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessingError.missingVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displayed = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        let frameRate = Double(try await track.load(.nominalFrameRate))
        let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        return VideoMetadata(
            duration: seconds,
            width: Int64(displayed.width.rounded()),
            height: Int64(displayed.height.rounded()),
            nominalFrameRate: frameRate,
            hasAudio: hasAudio
        )
    }

}
