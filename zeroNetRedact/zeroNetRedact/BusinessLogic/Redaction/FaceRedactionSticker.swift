import Foundation

/// 图片和视频共用的不透明人脸遮挡贴纸目录。
enum FaceRedactionSticker: String, CaseIterable, Identifiable, Sendable {
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
        NSLocalizedString("video.sticker.\(rawValue)", comment: "")
    }

    var description: String {
        NSLocalizedString("video.sticker.description.\(rawValue)", comment: "")
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

struct FaceStickerSelectionState: Equatable, Sendable {
    private(set) var selected: FaceRedactionSticker = .orangeSmiley
    private(set) var pendingPremiumSticker: FaceRedactionSticker?

    @discardableResult
    mutating func request(
        _ sticker: FaceRedactionSticker,
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

    mutating func resolvePremiumRequest(hasUnlimitedAccess: Bool) -> FaceRedactionSticker? {
        defer { pendingPremiumSticker = nil }
        guard hasUnlimitedAccess, let pendingPremiumSticker else { return nil }
        selected = pendingPremiumSticker
        return selected
    }

    mutating func cancelPremiumRequest() {
        pendingPremiumSticker = nil
    }
}
