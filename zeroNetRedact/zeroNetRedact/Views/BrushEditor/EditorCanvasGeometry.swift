import CoreGraphics
import Foundation

/// Window dimensions affect presentation only; media coordinates remain stable.
enum EditorCanvasGeometry {
    nonisolated static func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: point.x / size.width, y: point.y / size.height)
    }

    nonisolated static func normalized(_ offset: CGSize, in size: CGSize) -> CGSize {
        let point = normalized(CGPoint(x: offset.width, y: offset.height), in: size)
        return CGSize(width: point.x, height: point.y)
    }

    nonisolated static func strokeBounds(points: [CGPoint], padding: CGSize, in size: CGSize) -> CGRect? {
        guard let first = points.first, size.width > 0, size.height > 0 else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: (minX - padding.width) * size.width,
                      y: (minY - padding.height) * size.height,
                      width: (maxX - minX + 2 * padding.width) * size.width,
                      height: (maxY - minY + 2 * padding.height) * size.height)
    }
}

enum EditorWorkspaceLayout {
    nonisolated static func usesInspector(in size: CGSize) -> Bool {
        // Leave room for a useful canvas and a scrollable tool column, including on iPad windows.
        size.width >= 700 && size.height >= 300
    }

    nonisolated static func inspectorWidth(in size: CGSize) -> CGFloat {
        min(380, max(340, size.width * 0.36))
    }

    nonisolated static func usesVideoColumns(in size: CGSize) -> Bool {
        size.width >= 700 && size.height >= 300
    }
}
