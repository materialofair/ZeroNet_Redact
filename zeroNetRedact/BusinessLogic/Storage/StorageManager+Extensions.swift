import Foundation

extension StorageManager {
    func deleteFile(id: UUID, type: FileType) throws {
        let originalURL = getOriginalFileURL(id: id, type: type)
        let thumbnailURL = getThumbnailURL(id: id, type: type)

        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: thumbnailURL)
    }

    private func getOriginalFileURL(id: UUID, type: FileType) -> URL {
        let originalsURL = documentsURL.appendingPathComponent("Originals")
        let typeDir = originalsURL.appendingPathComponent(type == .image ? "Images" : "PDFs")
        return typeDir.appendingPathComponent("\(id.uuidString).encrypted")
    }

    private func getThumbnailURL(id: UUID, type: FileType) -> URL {
        let thumbnailsURL = documentsURL.appendingPathComponent("Thumbnails")
        let typeDir = thumbnailsURL.appendingPathComponent(type == .image ? "Images" : "PDFs")
        return typeDir.appendingPathComponent("\(id.uuidString).jpg")
    }
}
