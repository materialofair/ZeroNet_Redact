import CoreGraphics
import Foundation

struct FaceTrackSmoother {
    struct Track {
        let id: Int
        var rect: CGRect
        var missedFrames: Int
    }

    private(set) var tracks: [Track] = []
    private(set) var createdTrackCount = 0
    let maximumMissedFrames: Int
    let smoothing: CGFloat

    nonisolated init(maximumMissedFrames: Int = 5, smoothing: CGFloat = 0.55) {
        self.maximumMissedFrames = maximumMissedFrames
        self.smoothing = smoothing
    }

    nonisolated mutating func update(with detections: [CGRect]) -> [CGRect] {
        var unmatchedDetectionIndices = Set(detections.indices)
        var nextTracks: [Track] = []

        for var track in tracks {
            let best = unmatchedDetectionIndices
                .map { index in (index, matchScore(track.rect, detections[index])) }
                .filter { $0.1 > 0.12 }
                .max { $0.1 < $1.1 }

            if let (index, _) = best {
                track.rect = interpolate(from: track.rect, to: detections[index], amount: smoothing)
                track.missedFrames = 0
                unmatchedDetectionIndices.remove(index)
                nextTracks.append(track)
            } else if track.missedFrames < maximumMissedFrames {
                track.missedFrames += 1
                let growth = 1 + CGFloat(track.missedFrames) * 0.04
                track.rect = expand(track.rect, scale: growth).clampedToUnitSquare
                nextTracks.append(track)
            }
        }

        for index in unmatchedDetectionIndices.sorted() {
            createdTrackCount += 1
            nextTracks.append(Track(id: createdTrackCount, rect: detections[index], missedFrames: 0))
        }

        tracks = nextTracks
        return tracks.map(\.rect)
    }

    private nonisolated func matchScore(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height
            - max(0, intersection.width) * max(0, intersection.height)
        let iou = unionArea > 0
            ? max(0, intersection.width) * max(0, intersection.height) / unionArea : 0
        let dx = lhs.midX - rhs.midX
        let dy = lhs.midY - rhs.midY
        let centerScore = max(0, 1 - sqrt(dx * dx + dy * dy) * 3)
        return max(iou, centerScore * 0.5)
    }

    private nonisolated func interpolate(from: CGRect, to: CGRect, amount: CGFloat) -> CGRect {
        CGRect(
            x: from.origin.x + (to.origin.x - from.origin.x) * amount,
            y: from.origin.y + (to.origin.y - from.origin.y) * amount,
            width: from.width + (to.width - from.width) * amount,
            height: from.height + (to.height - from.height) * amount
        ).clampedToUnitSquare
    }

    private nonisolated func expand(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.midX - rect.width * scale / 2,
            y: rect.midY - rect.height * scale / 2,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}
