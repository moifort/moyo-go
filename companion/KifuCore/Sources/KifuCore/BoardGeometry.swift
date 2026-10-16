import Foundation

/// The four grid corners tapped by the user, in image pixels (origin top-left).
/// Order: top-left, top-right, bottom-right, bottom-left of the grid as seen in the image.
public struct Calibration: Sendable, Equatable, Codable {
    public let lines: Int
    public let corners: [Point]

    public init(lines: Int = 19, corners: [Point]) {
        precondition(corners.count == 4)
        self.lines = lines
        self.corners = corners
    }
}


/// Maps board coordinates (in line spacings, intersection (col,row) at (col,row)) to image pixels.
public struct BoardGeometry: Sendable {
    public let lines: Int
    public let toImage: Homography
    public let toBoard: Homography
    /// Unit vector in board coordinates pointing away from the camera (from the near edge to the far one).
    public let awayFromCamera: (Double, Double)
    /// Smallest image distance between two neighbouring intersections.
    public let minSpacing: Double

    public init?(calibration: Calibration) {
        lines = calibration.lines
        let n = Double(lines - 1)
        let src = [Point(x: 0, y: 0), Point(x: n, y: 0), Point(x: n, y: n), Point(x: 0, y: n)]
        guard let h = Homography(from: src, to: calibration.corners), let inv = h.inverted() else { return nil }
        toImage = h
        toBoard = inv

        func edgeSpacing(_ points: [Point]) -> Double {
            zip(points.dropFirst(), points).map { Self.distance($0, $1) }.reduce(0, +) / Double(points.count - 1)
        }
        let top = edgeSpacing((0..<lines).map { h.apply(Point(x: Double($0), y: 0)) })
        let bottom = edgeSpacing((0..<lines).map { h.apply(Point(x: Double($0), y: n)) })
        let left = edgeSpacing((0..<lines).map { h.apply(Point(x: 0, y: Double($0))) })
        let right = edgeSpacing((0..<lines).map { h.apply(Point(x: n, y: Double($0))) })
        // Perspective shrinks the far edge: the near/far pair is the most asymmetric one,
        // and within it the wider edge is the near one.
        let verticalRatio = max(top, bottom) / min(top, bottom)
        let horizontalRatio = max(left, right) / min(left, right)
        if verticalRatio >= horizontalRatio {
            awayFromCamera = top > bottom ? (0, 1) : (0, -1)
        } else {
            awayFromCamera = left > right ? (1, 0) : (-1, 0)
        }

        var minimum = Double.infinity
        for row in 0..<lines {
            for col in 0..<lines {
                let p = h.apply(Point(x: Double(col), y: Double(row)))
                if col + 1 < lines { minimum = min(minimum, Self.distance(p, h.apply(Point(x: Double(col + 1), y: Double(row))))) }
                if row + 1 < lines { minimum = min(minimum, Self.distance(p, h.apply(Point(x: Double(col), y: Double(row + 1))))) }
            }
        }
        minSpacing = minimum
    }

    public func imagePoint(of i: Intersection) -> Point {
        toImage.apply(Point(x: Double(i.col), y: Double(i.row)))
    }

    public func imagePoint(boardX: Double, boardY: Double) -> Point {
        toImage.apply(Point(x: boardX, y: boardY))
    }

    static func distance(_ a: Point, _ b: Point) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    // MARK: Corner refinement

    /// Minimum darkness gain of a line over the wood to accept a refinement.
    static let lineContrast = 20.0

    /// Snaps each tapped corner to the nearest crossing of two inward grid lines, searching
    /// within `radius` pixels. A corner without a visible crossing (covered by a stone) is returned as tapped.
    public static func refineCorners(_ taps: [Point], lines: Int, in image: GrayImage, radius: Int) -> [Point] {
        guard taps.count == 4, let geometry = BoardGeometry(calibration: Calibration(lines: lines, corners: taps)) else { return taps }
        let n = Double(lines - 1)
        let boardCorners = [(0.0, 0.0), (n, 0.0), (n, n), (0.0, n)]
        let inward: [[(Double, Double)]] = [[(1, 0), (0, 1)], [(-1, 0), (0, 1)], [(-1, 0), (0, -1)], [(1, 0), (0, -1)]]
        return taps.indices.map { k in
            let (bx, by) = boardCorners[k]
            let origin = geometry.imagePoint(boardX: bx, boardY: by)
            let segments = inward[k].map { d -> (Double, Double) in
                let end = geometry.imagePoint(boardX: bx + 0.6 * d.0, boardY: by + 0.6 * d.1)
                return (end.x - origin.x, end.y - origin.y)
            }
            let diagonal = inward[k].reduce((0.0, 0.0)) { ($0.0 + $1.0, $0.1 + $1.1) }
            let cell = geometry.imagePoint(boardX: bx + 0.5 * diagonal.0, boardY: by + 0.5 * diagonal.1)
            let quarter = geometry.imagePoint(boardX: bx + 0.25 * diagonal.0, boardY: by + 0.25 * diagonal.1)

            func darkness(at p: Point) -> Double { 255 - image.sample(x: p.x, y: p.y) }
            func lineScore(at p: Point) -> Double {
                var sum = 0.0, count = 0.0
                for (dx, dy) in segments {
                    for t in stride(from: 0.1, through: 1.0, by: 0.1) {
                        sum += darkness(at: Point(x: p.x + dx * t, y: p.y + dy * t)); count += 1
                    }
                }
                return sum / count
            }

            var best = taps[k], bestScore = -Double.infinity
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let p = Point(x: taps[k].x + Double(dx), y: taps[k].y + Double(dy))
                    let s = lineScore(at: p)
                    if s > bestScore { bestScore = s; best = p }
                }
            }
            let shift = (best.x - taps[k].x, best.y - taps[k].y)
            let wood = darkness(at: Point(x: cell.x + shift.0, y: cell.y + shift.1))
            let inside = darkness(at: Point(x: quarter.x + shift.0, y: quarter.y + shift.1))
            let isCrossing = bestScore >= wood + lineContrast && inside <= bestScore - lineContrast
            return isCrossing ? best : taps[k]
        }
    }
}
