import CoreGraphics
import Foundation

struct ImageFaceCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    let rect: CGRect

    init(id: UUID = UUID(), rect: CGRect) {
        self.id = id
        self.rect = rect
    }
}

struct ImageFaceReviewState: Equatable, Sendable {
    private(set) var candidates: [ImageFaceCandidate]
    private(set) var selectedIDs: Set<UUID>

    init(candidates: [ImageFaceCandidate] = []) {
        self.candidates = candidates
        selectedIDs = Set(candidates.map(\.id))
    }

    mutating func toggle(_ id: UUID) {
        guard candidates.contains(where: { $0.id == id }) else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    mutating func selectAll() {
        selectedIDs = Set(candidates.map(\.id))
    }

    mutating func deselectAll() {
        selectedIDs.removeAll()
    }

    var selectedCandidates: [ImageFaceCandidate] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    static func excludingAlreadyProtected(
        _ candidates: [ImageFaceCandidate],
        existingRects: [CGRect],
        threshold: CGFloat = 0.70
    ) -> [ImageFaceCandidate] {
        candidates.filter { candidate in
            !existingRects.contains {
                candidate.rect.intersectionOverUnion(with: $0) >= threshold
            }
        }
    }
}

enum ImageEditorPremiumIntent: Equatable, Sendable {
    case faceSticker(FaceRedactionSticker)
    case export
}

enum ImageEditorPremiumDismissalAction: Equatable, Sendable {
    case none
    case applySticker(FaceRedactionSticker)
    case retryExport
}

struct ImageEditorPremiumIntentState: Equatable, Sendable {
    private(set) var current: ImageEditorPremiumIntent?

    mutating func present(_ intent: ImageEditorPremiumIntent) {
        current = intent
    }

    mutating func resolveDismissal(
        hasUnlimitedAccess: Bool,
        selection: inout FaceStickerSelectionState
    ) -> ImageEditorPremiumDismissalAction {
        defer { current = nil }
        switch current {
        case .faceSticker:
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
