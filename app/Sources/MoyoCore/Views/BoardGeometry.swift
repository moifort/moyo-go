import CoreGraphics

/// Maps between board intersections and points inside a square board view.
///
/// Pure geometry: it knows nothing about rules, stones or the bridge, which is what
/// makes the click-to-intersection conversion testable on its own.
public struct BoardGeometry: Sendable, Equatable {
    public let size: Int
    public let side: CGFloat

    /// One grid step. The wood reaches `woodMargin` steps past the outer lines, and
    /// the coordinates sit in a band of `labelBand` steps outside it, on the left and
    /// at the bottom: a 19x19 grid divides the side into 18 + 2 × 0.79 + 1 steps.
    public var step: CGFloat { side / (CGFloat(size - 1) + 2 * Self.woodMargin + Self.labelBand) }
    public var stoneRadius: CGFloat { step * 13 / 28 }
    public var lineWidth: CGFloat { max(0.5, step * 0.8 / 28) }
    public var starRadius: CGFloat { max(1.5, step * 3 / 28) }
    public var labelSize: CGFloat { step * 12 / 28 }

    static let woodMargin: CGFloat = 22.0 / 28
    static let labelBand: CGFloat = 1

    /// The top-left intersection.
    var origin: CGPoint { CGPoint(x: (Self.labelBand + Self.woodMargin) * step, y: Self.woodMargin * step) }

    /// The wood, square, with the grid centred on it.
    public var woodRect: CGRect {
        let inset = Self.woodMargin * step
        return CGRect(
            x: origin.x - inset, y: origin.y - inset,
            width: CGFloat(size - 1) * step + 2 * inset, height: CGFloat(size - 1) * step + 2 * inset
        )
    }

    public var woodCornerRadius: CGFloat { woodRect.width * 4 / 548 }

    public init(size: Int, side: CGFloat) {
        self.size = max(2, size)
        self.side = max(1, side)
    }

    public func position(row: Int, col: Int) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(col) * step, y: origin.y + CGFloat(row) * step)
    }

    public func position(of point: Point) -> CGPoint {
        position(row: point.row, col: point.col)
    }

    /// The letter of a column, I left out as on every board.
    public static func columnLabel(_ col: Int) -> String {
        let letters = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")
        return col < letters.count ? String(letters[col]) : String(col + 1)
    }

    /// The number of a row, counted from the bottom.
    public func rowLabel(_ row: Int) -> String { String(size - row) }

    /// Where a column's letter is centred, below the wood.
    public func columnLabelPosition(_ col: Int) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(col) * step, y: woodRect.maxY + step * 18 / 28)
    }

    /// Where a row's number ends, left of the wood.
    public func rowLabelPosition(_ row: Int) -> CGPoint {
        CGPoint(x: woodRect.minX - step * 12 / 28, y: origin.y + CGFloat(row) * step)
    }

    /// The intersection under a point, or nil when the point is too far from any.
    ///
    /// The tolerance is half a step, so the whole board surface maps to some
    /// intersection while clicks in the outer margin fall through.
    public func intersection(at location: CGPoint) -> Point? {
        let col = ((location.x - origin.x) / step).rounded()
        let row = ((location.y - origin.y) / step).rounded()
        guard col >= 0, col <= CGFloat(size - 1), row >= 0, row <= CGFloat(size - 1) else { return nil }
        let nearest = CGPoint(x: origin.x + col * step, y: origin.y + row * step)
        let dx = location.x - nearest.x
        let dy = location.y - nearest.y
        guard (dx * dx + dy * dy).squareRoot() <= step / 2 else { return nil }
        return Point(row: Int(row), col: Int(col))
    }

    /// The intersection nearest a point, wherever it lies: a drag that strays into
    /// the margin or off the board still ends on its edge.
    public func nearestIntersection(to location: CGPoint) -> Point {
        let last = CGFloat(size - 1)
        let col = min(max(((location.x - origin.x) / step).rounded(), 0), last)
        let row = min(max(((location.y - origin.y) / step).rounded(), 0), last)
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
