import AVFoundation
import CoreGraphics
import Foundation

/// 视频 API 保持源码兼容；目录和选择状态由图片/视频共享。
typealias VideoRedactionSticker = FaceRedactionSticker
typealias VideoStickerSelectionState = FaceStickerSelectionState

enum VideoPremiumIntent: Equatable, Sendable {
    case sticker(VideoRedactionSticker)
    case export
}

enum VideoPremiumDismissalAction: Equatable, Sendable {
    case none
    case applySticker(VideoRedactionSticker)
    case retryExport
}

struct VideoPremiumIntentState: Equatable, Sendable {
    private(set) var current: VideoPremiumIntent?

    mutating func present(_ intent: VideoPremiumIntent) {
        current = intent
    }

    mutating func consume() -> VideoPremiumIntent? {
        defer { current = nil }
        return current
    }

    mutating func resolveDismissal(
        hasUnlimitedAccess: Bool,
        selection: inout VideoStickerSelectionState
    ) -> VideoPremiumDismissalAction {
        switch consume() {
        case .sticker:
            guard let sticker = selection.resolvePremiumRequest(
                hasUnlimitedAccess: hasUnlimitedAccess
            ) else { return .none }
            return .applySticker(sticker)
        case .export:
            selection.cancelPremiumRequest()
            return hasUnlimitedAccess ? .retryExport : .none
        case nil:
            selection.cancelPremiumRequest()
            return .none
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
