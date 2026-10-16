import Foundation

public struct Point: Sendable, Equatable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Planar 3x3 homography estimated from four point correspondences.
public struct Homography: Sendable, Equatable {
    /// Row-major 3x3 matrix; m[8] is 1 after estimation.
    public let m: [Double]

    public init(matrix m: [Double]) {
        precondition(m.count == 9)
        self.m = m
    }

    /// Four-point DLT solved as an 8x8 linear system.
    public init?(from src: [Point], to dst: [Point]) {
        guard src.count == 4, dst.count == 4 else { return nil }
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let (x, y) = (src[i].x, src[i].y)
            let (u, v) = (dst[i].x, dst[i].y)
            a[2 * i]     = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        guard let h = Homography.solve(a) else { return nil }
        self.m = h + [1]
    }

    public func apply(_ p: Point) -> Point {
        let w = m[6] * p.x + m[7] * p.y + m[8]
        return Point(x: (m[0] * p.x + m[1] * p.y + m[2]) / w,
                     y: (m[3] * p.x + m[4] * p.y + m[5]) / w)
    }

    public func inverted() -> Homography? {
        let (a, b, c, d, e, f, g, h, i) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        guard abs(det) > 1e-12 else { return nil }
        let inv = [
            (e * i - f * h), -(b * i - c * h),  (b * f - c * e),
           -(d * i - f * g),  (a * i - c * g), -(a * f - c * d),
            (d * h - e * g), -(a * h - b * g),  (a * e - b * d),
        ].map { $0 / det }
        return Homography(matrix: inv)
    }

    /// Gauss-Jordan with partial pivoting on an 8x9 augmented matrix. Nil when singular.
    static func solve(_ input: [[Double]]) -> [Double]? {
        var a = input
        let n = 8
        for col in 0..<n {
            var pivot = col
            for r in (col + 1)..<n where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            guard abs(a[pivot][col]) > 1e-9 else { return nil }
            a.swapAt(col, pivot)
            for r in 0..<n where r != col {
                let factor = a[r][col] / a[col][col]
                if factor != 0 {
                    for k in col..<(n + 1) { a[r][k] -= factor * a[col][k] }
                }
            }
        }
        return (0..<n).map { a[$0][n] / a[$0][$0] }
    }
}
