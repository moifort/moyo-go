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

    /// The camera behind the homography, for a frame of the given size: the focal length that
    /// makes the board's two axes perpendicular (principal point at the frame centre), and the
    /// pose. Nil when the view is too frontal to tell.
    public struct Camera: Sendable {
        let k: [Double]          // row-major 3x3 intrinsics
        let r: [[Double]]        // columns r1, r2, r3 of the rotation
        let t: [Double]
        public let focal: Double

        /// The camera centre in board coordinates: where it stands over the board, and how high.
        public var foot: Point { Point(x: -(r[0][0] * t[0] + r[0][1] * t[1] + r[0][2] * t[2]), y: -(r[1][0] * t[0] + r[1][1] * t[1] + r[1][2] * t[2])) }
        public var height: Double { -(r[2][0] * t[0] + r[2][1] * t[1] + r[2][2] * t[2]) }

        /// Image of the point `height` spacings above board point `p`.
        public func project(_ p: Point, height: Double) -> Point {
            var c = [0.0, 0.0, 0.0]
            for i in 0..<3 { c[i] = r[0][i] * p.x + r[1][i] * p.y + r[2][i] * height + t[i] }
            let u = k[0] * c[0] + k[1] * c[1] + k[2] * c[2]
            let v = k[3] * c[0] + k[4] * c[1] + k[5] * c[2]
            let w = k[6] * c[0] + k[7] * c[1] + k[8] * c[2]
            return Point(x: u / w, y: v / w)
        }
    }

    /// The camera that sees the board through `toImage`, for stones' height. `focal`, in pixels
    /// of this image, is the one found at calibration: read from the corners alone it is
    /// ill-conditioned, a board seen square from its middle leaving one vanishing point near
    /// infinity. Three pixels on the far corners then take it from 3000 px to no camera at all.
    public func camera(imageWidth: Int, imageHeight: Int, focal: Double? = nil) -> Camera? {
        let m = toImage.m
        let cx = Double(imageWidth) / 2, cy = Double(imageHeight) / 2
        let h1 = (m[0], m[3], m[6]), h2 = (m[1], m[4], m[7]), h3 = (m[2], m[5], m[8])
        // With K = diag(f, f, 1) about (cx, cy), r1 ⊥ r2 fixes f.
        let a1 = h1.0 - cx * h1.2, b1 = h1.1 - cy * h1.2
        let a2 = h2.0 - cx * h2.2, b2 = h2.1 - cy * h2.2
        let f: Double
        if let focal {
            f = focal
        } else {
            let f2 = -(a1 * a2 + b1 * b2) / (h1.2 * h2.2)
            guard f2.isFinite, f2 > 0 else { return nil }
            f = f2.squareRoot()
        }
        let longest = Double(max(imageWidth, imageHeight))
        guard f > 0.3 * longest, f < 6 * longest else { return nil }
        var m1 = [a1 / f, b1 / f, h1.2], m2 = [a2 / f, b2 / f, h2.2]
        var m3 = [(h3.0 - cx * h3.2) / f, (h3.1 - cy * h3.2) / f, h3.2]
        let scale = 1 / (m1[0] * m1[0] + m1[1] * m1[1] + m1[2] * m1[2]).squareRoot()
        // The board lies in front of the camera: its origin has a positive depth.
        let sign: Double = m3[2] * scale > 0 ? 1 : -1
        for i in 0..<3 { m1[i] *= scale * sign; m2[i] *= scale * sign; m3[i] *= scale * sign }
        var r3 = [m1[1] * m2[2] - m1[2] * m2[1], m1[2] * m2[0] - m1[0] * m2[2], m1[0] * m2[1] - m1[1] * m2[0]]
        // Up is towards the camera: the camera centre -Rᵀt must sit above the board.
        let camZ = -(r3[0] * m3[0] + r3[1] * m3[1] + r3[2] * m3[2])
        if camZ < 0 { r3 = r3.map { -$0 } }
        return Camera(k: [f, 0, cx, 0, f, cy, 0, 0, 1], r: [m1, m2, r3], t: m3, focal: f)
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

    // MARK: Global grid fit

    /// Contrast of every grid line: darkness on the line minus darkness a third of a spacing
    /// to either side, so broad dark areas (shadows, table, board edge) do not attract the fit.
    static func gridScore(_ corners: [Point], lines: Int, in image: GrayImage, samplesPerLine: Int = 40) -> Double {
        guard let g = BoardGeometry(calibration: Calibration(lines: lines, corners: corners)) else { return -.infinity }
        let n = Double(lines - 1)
        let side = 0.33
        func darkness(_ x: Double, _ y: Double) -> Double {
            let p = g.imagePoint(boardX: x, boardY: y)
            return 255 - image.sample(x: p.x, y: p.y)
        }
        var sum = 0.0
        for k in 0..<lines {
            let t = Double(k)
            for s in 0..<samplesPerLine {
                let u = n * (Double(s) + 0.5) / Double(samplesPerLine)
                sum += darkness(t, u) - (darkness(t - side, u) + darkness(t + side, u)) / 2
                sum += darkness(u, t) - (darkness(u, t - side) + darkness(u, t + side)) / 2
            }
        }
        return sum / Double(2 * lines * samplesPerLine)
    }

    /// Moves the four corners, within `radius` pixels each, to maximise the darkness along all
    /// grid lines. Robust to stones on the corners since every line contributes. Besides one
    /// corner at a time, the whole grid is tried shifted as one: a nudged stand moves all four
    /// together, and no single corner improves the score on its own.
    public static func fitCorners(_ taps: [Point], lines: Int, in image: GrayImage, radius: Int) -> [Point] {
        guard taps.count == 4 else { return taps }
        var best = taps
        var bestScore = gridScore(best, lines: lines, in: image)
        var step = Double(max(radius / 2, 1))
        while step >= 0.5 {
            var improved = true
            while improved {
                improved = false
                for (dx, dy) in [(step, 0.0), (-step, 0.0), (0.0, step), (0.0, -step)] {
                    for moved in [[0], [1], [2], [3], [0, 1, 2, 3]] {
                        var candidate = best
                        for k in moved { candidate[k] = Point(x: best[k].x + dx, y: best[k].y + dy) }
                        guard moved.allSatisfy({ abs(candidate[$0].x - taps[$0].x) <= Double(radius) && abs(candidate[$0].y - taps[$0].y) <= Double(radius) }) else { continue }
                        let score = gridScore(candidate, lines: lines, in: image)
                        if score > bestScore + 1e-9 { bestScore = score; best = candidate; improved = true }
                    }
                }
            }
            step /= 2
        }
        return best
    }
}
