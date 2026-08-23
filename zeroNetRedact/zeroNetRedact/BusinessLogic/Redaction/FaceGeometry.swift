import CoreGraphics

extension CGRect {
    nonisolated var clampedToUnitSquare: CGRect {
        intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    nonisolated func expandedForPrivacy(scale: CGFloat = 1.3) -> CGRect {
        CGRect(
            x: midX - width * scale / 2,
            y: midY - height * scale / 2,
            width: width * scale,
            height: height * scale
        ).clampedToUnitSquare
    }

    nonisolated func intersectionOverUnion(with other: CGRect) -> CGFloat {
        let lhs = standardized
        let rhs = other.standardized
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let overlap = lhs.intersection(rhs)
        guard !overlap.isNull, !overlap.isEmpty else { return 0 }
        let intersectionArea = overlap.width * overlap.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}
