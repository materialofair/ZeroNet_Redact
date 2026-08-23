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
    case heartEyes
    case robot
    case clown
    case lion

    enum Artwork: Equatable, Sendable {
        case systemImage(String)
        case asset(String)
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .orangeSmiley: return NSLocalizedString("video.sticker.orangeSmiley", comment: "")
        case .blueSmiley: return NSLocalizedString("video.sticker.blueSmiley", comment: "")
        case .sunglasses: return NSLocalizedString("video.sticker.sunglasses", comment: "")
        case .panda: return NSLocalizedString("video.sticker.panda", comment: "")
        case .alien: return NSLocalizedString("video.sticker.alien", comment: "")
        case .heartEyes: return NSLocalizedString("video.sticker.heartEyes", comment: "")
        case .robot: return NSLocalizedString("video.sticker.robot", comment: "")
        case .clown: return NSLocalizedString("video.sticker.clown", comment: "")
        case .lion: return NSLocalizedString("video.sticker.lion", comment: "")
        }
    }

    var description: String {
        switch self {
        case .orangeSmiley:
            return NSLocalizedString("video.sticker.description.orangeSmiley", comment: "")
        case .blueSmiley:
            return NSLocalizedString("video.sticker.description.blueSmiley", comment: "")
        case .sunglasses:
            return NSLocalizedString("video.sticker.description.sunglasses", comment: "")
        case .panda:
            return NSLocalizedString("video.sticker.description.panda", comment: "")
        case .alien:
            return NSLocalizedString("video.sticker.description.alien", comment: "")
        case .heartEyes:
            return NSLocalizedString("video.sticker.description.heartEyes", comment: "")
        case .robot:
            return NSLocalizedString("video.sticker.description.robot", comment: "")
        case .clown:
            return NSLocalizedString("video.sticker.description.clown", comment: "")
        case .lion:
            return NSLocalizedString("video.sticker.description.lion", comment: "")
        }
    }

    var artwork: Artwork {
        switch self {
        case .orangeSmiley: return .systemImage("face.smiling.inverse")
        case .blueSmiley: return .systemImage("face.smiling")
        case .sunglasses: return .asset("StickerSunglasses")
        case .panda: return .asset("StickerPanda")
        case .alien: return .asset("StickerAlien")
        case .heartEyes: return .asset("StickerHeartEyes")
        case .robot: return .asset("StickerRobot")
        case .clown: return .asset("StickerClown")
        case .lion: return .asset("StickerLion")
        }
    }

    var requiresPremium: Bool {
        self != .orangeSmiley && self != .blueSmiley
    }

    func isLocked(hasUnlimitedAccess: Bool) -> Bool {
        requiresPremium && !hasUnlimitedAccess
    }

    func accessibilityValue(hasUnlimitedAccess: Bool) -> String {
        isLocked(hasUnlimitedAccess: hasUnlimitedAccess)
            ? NSLocalizedString("video.sticker.accessibility.premium", comment: "")
            : NSLocalizedString("video.sticker.accessibility.available", comment: "")
    }
}

struct VideoStickerSelectionState: Equatable, Sendable {
    private(set) var selected: VideoRedactionSticker = .orangeSmiley
    private(set) var pendingPremiumSticker: VideoRedactionSticker?

    @discardableResult
    mutating func request(
        _ sticker: VideoRedactionSticker,
        hasUnlimitedAccess: Bool
    ) -> Bool {
        guard !sticker.isLocked(hasUnlimitedAccess: hasUnlimitedAccess) else {
            pendingPremiumSticker = sticker
            return false
        }
        selected = sticker
        pendingPremiumSticker = nil
        return true
    }

    mutating func resolvePremiumRequest(hasUnlimitedAccess: Bool) -> VideoRedactionSticker? {
        defer { pendingPremiumSticker = nil }
        guard hasUnlimitedAccess, let pendingPremiumSticker else { return nil }
        selected = pendingPremiumSticker
        return selected
    }

    mutating func cancelPremiumRequest() {
        pendingPremiumSticker = nil
    }
}

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
