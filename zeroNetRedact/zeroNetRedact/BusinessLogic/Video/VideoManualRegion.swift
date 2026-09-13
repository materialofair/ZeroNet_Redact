import Foundation
import CoreGraphics

struct VideoManualRegion: Codable, Identifiable, Sendable {
    var id = UUID()
    let rect: CGRect
    let start: Double
    let end: Double
    var effect = "blur"

    init?(rect: CGRect, start: Double, end: Double, duration: Double) {
        guard start.isFinite, end.isFinite, duration.isFinite,
              start >= 0, start < end, end <= duration,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }),
              rect.width > 0, rect.height > 0,
              rect.minX >= 0, rect.minY >= 0, rect.maxX <= 1, rect.maxY <= 1 else { return nil }
        self.rect = rect
        self.start = start
        self.end = end
    }

    func contains(_ seconds: Double) -> Bool { seconds >= start && seconds < end }

    func redrawing(rect: CGRect, duration: Double) -> VideoManualRegion? {
        guard var candidate = VideoManualRegion(rect: rect, start: start, end: end, duration: duration) else { return nil }
        candidate.id = id
        candidate.effect = effect
        return candidate
    }
}

/// Groups spatial tracking segments chosen by the user; these are not biometric identities.
struct VideoPersonGroup: Codable, Identifiable, Sendable {
    var id = UUID()
    var trackIDs: [Int]
    var effect: String
}
