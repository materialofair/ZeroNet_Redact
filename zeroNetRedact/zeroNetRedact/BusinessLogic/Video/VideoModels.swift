import AVFoundation
import CoreGraphics
import Foundation

/// 视频人脸遮挡统一使用不透明卡通贴纸（不再提供强模糊）。
enum VideoRedactionSticker: String, CaseIterable, Identifiable, Sendable {
    case orangeSmiley
    case blueSmiley
    case sunglasses
    case panda
    case alien

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .orangeSmiley: return NSLocalizedString("video.sticker.orangeSmiley", comment: "")
        case .blueSmiley: return NSLocalizedString("video.sticker.blueSmiley", comment: "")
        case .sunglasses: return NSLocalizedString("video.sticker.sunglasses", comment: "")
        case .panda: return NSLocalizedString("video.sticker.panda", comment: "")
        case .alien: return NSLocalizedString("video.sticker.alien", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .orangeSmiley: return "face.smiling.inverse"
        case .blueSmiley: return "face.smiling"
        case .sunglasses: return "sunglasses.fill"
        case .panda: return "pawprint.fill"
        case .alien: return "face.dashed"
        }
    }
}

struct VideoFaceFrame: Sendable {
    let seconds: Double
    let normalizedRects: [CGRect]
}

struct VideoFaceTimeline: Sendable {
    let frames: [VideoFaceFrame]
    let frameRate: Double
    let totalUniqueFaces: Int

    static let empty = VideoFaceTimeline(frames: [], frameRate: 30, totalUniqueFaces: 0)

    func rects(at time: CMTime) -> [CGRect] {
        guard !frames.isEmpty else { return [] }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return frames[0].normalizedRects }

        var low = 0
        var high = frames.count - 1
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].seconds < seconds {
                low = middle + 1
            } else {
                high = middle
            }
        }
        if low == 0 { return frames[0].normalizedRects }
        let before = frames[low - 1]
        let after = frames[low]
        return seconds - before.seconds <= after.seconds - seconds
            ? before.normalizedRects : after.normalizedRects
    }
}

struct VideoMetadata: Sendable {
    let duration: Double
    let width: Int64
    let height: Int64
    let nominalFrameRate: Double
    let hasAudio: Bool
}

enum VideoPlaybackTime {
    static func resumeTime(from player: AVPlayer) -> CMTime? {
        guard player.currentItem != nil else { return nil }
        return validated(player.currentTime())
    }

    static func validated(_ time: CMTime) -> CMTime? {
        let seconds = CMTimeGetSeconds(time)
        guard time.isValid, time.isNumeric, seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return time
    }
}

enum VideoProcessingError: LocalizedError {
    case missingVideoTrack
    case invalidDuration
    case unableToCreateThumbnail
    case unableToCreateComposition
    case unableToCreateExporter
    case exportFailed(String)
    case unexpectedVideoCodec
    case missingAudioTrack
    case duplicate
    case noFacesDetected

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return NSLocalizedString("video.error.missingTrack", comment: "")
        case .invalidDuration:
            return NSLocalizedString("video.error.invalidDuration", comment: "")
        case .unableToCreateThumbnail:
            return NSLocalizedString("video.error.thumbnail", comment: "")
        case .unableToCreateComposition, .unableToCreateExporter:
            return NSLocalizedString("video.error.exportUnavailable", comment: "")
        case .exportFailed(let message):
            return message
        case .unexpectedVideoCodec:
            return NSLocalizedString("video.error.h264Required", comment: "")
        case .missingAudioTrack:
            return NSLocalizedString("video.error.missingAudioTrack", comment: "")
        case .duplicate:
            return NSLocalizedString("import.duplicate.single", comment: "")
        case .noFacesDetected:
            return NSLocalizedString("video.warning.noFaces", comment: "")
        }
    }
}
