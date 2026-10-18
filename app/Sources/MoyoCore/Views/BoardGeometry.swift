import CoreGraphics

/// Maps between board intersections and points inside a square board view.
///
/// Pure geometry: it knows nothing about rules, stones or the bridge, which is what
/// makes the click-to-intersection conversion testable on its own.
public struct BoardGeometry: Sendable, Equatable {
    public let size: Int
    public let side: CGFloat

    /// One grid step. The board is laid out with a one-step margin on each edge, so
    /// a 19x19 grid divides the side into 20.
    public var step: CGFloat { side / CGFloat(size + 1) }
    public var margin: CGFloat { step }
    public var stoneRadius: CGFloat { step * 0.47 }
    public var lineWidth: CGFloat { max(0.5, step * 0.045) }
    public var starRadius: CGFloat { max(1.5, step * 0.14) }

    public init(size: Int, side: CGFloat) {
        self.size = max(2, size)
        self.side = max(1, side)
    }

    public func position(row: Int, col: Int) -> CGPoint {
        CGPoint(x: margin + CGFloat(col) * step, y: margin + CGFloat(row) * step)
    }

    public func position(of point: Point) -> CGPoint {
        position(row: point.row, col: point.col)
    }

    /// The intersection under a point, or nil when the point is too far from any.
    ///
    /// The tolerance is half a step, so the whole board surface maps to some
    /// intersection while clicks in the outer margin fall through.
    public func intersection(at location: CGPoint) -> Point? {
        let col = ((location.x - margin) / step).rounded()
        let row = ((location.y - margin) / step).rounded()
        guard col >= 0, col <= CGFloat(size - 1), row >= 0, row <= CGFloat(size - 1) else { return nil }
        let nearest = CGPoint(x: margin + col * step, y: margin + row * step)
        let dx = location.x - nearest.x
        let dy = location.y - nearest.y
        guard (dx * dx + dy * dy).squareRoot() <= step / 2 else { return nil }
        return Point(row: Int(row), col: Int(col))
    }

    /// The intersection nearest a point, wherever it lies: a drag that strays into
    /// the margin or off the board still ends on its edge.
    public func nearestIntersection(to location: CGPoint) -> Point {
        let last = CGFloat(size - 1)
        let col = min(max(((location.x - margin) / step).rounded(), 0), last)
        let row = min(max(((location.y - margin) / step).rounded(), 0), last)
        return Point(row: Int(row), col: Int(col))
    }

    /// Star points for the usual board sizes; empty for anything unconventional.
    public var starPoints: [Point] {
        let lines: [Int]
        switch size {
        case 19: lines = [3, 9, 15]
        case 13: lines = [3, 6, 9]
        case 9: lines = [2, 4, 6]
        default: return []
        }
        return lines.flatMap { row in lines.map { Point(row: row, col: $0) } }
    }
}
