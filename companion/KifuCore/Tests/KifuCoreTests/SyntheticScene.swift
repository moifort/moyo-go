import Foundation
@testable import KifuCore

/// Renders a goban seen through a homography, with optional lighting gradient and hard shadow.
/// Board coordinates are in line spacings: intersection (col, row) sits at (col, row).
struct SyntheticScene {
    var lines = 19
    var wood = 190.0
    var lineDarkness = 35.0
    var black = 25.0
    var white = 240.0
    var lineWidth = 0.05          // in spacings
    var stoneRadius = 0.47        // in spacings
    /// Stone thickness in spacings: the stone body is drawn where the reader expects it, so the
    /// scene and the reader agree by construction.
    var stoneHeight = 0.0
    var stones: [Intersection: Stone] = [:]
    /// Image-space lighting: multiplier as a function of (x, y) in pixels.
    var lighting: (Double, Double) -> Double = { _, _ in 1 }

    /// Corners in image pixels: top-left, top-right, bottom-right, bottom-left of the grid.
    var corners: [Point]
    var width: Int
    var height: Int

    /// A grazing view: the bottom (near) edge is wide, the top (far) edge narrow.
    static func grazing(width: Int = 900, height: Int = 675) -> [Point] {
        let s = Double(width) / 1200
        return [Point(x: 330 * s, y: 230 * s), Point(x: 870 * s, y: 230 * s), Point(x: 1130 * s, y: 820 * s), Point(x: 70 * s, y: 820 * s)]
    }

    init(width: Int = 900, height: Int = 675, corners: [Point]? = nil) {
        self.width = width
        self.height = height
        self.corners = corners ?? Self.grazing(width: width, height: height)
    }

    var calibration: Calibration { Calibration(lines: lines, corners: corners) }

    /// Unit vector in board coordinates pointing away from the camera.
    var awayFromCamera: (Double, Double) {
        BoardGeometry(calibration: calibration)!.awayFromCamera
    }

    func render() -> GrayImage {
        let n = Double(lines - 1)
        let src = [Point(x: 0, y: 0), Point(x: n, y: 0), Point(x: n, y: n), Point(x: 0, y: n)]
        let toImage = Homography(from: src, to: corners)!
        let toBoard = toImage.inverted()!
        var shifts: [Intersection: (Double, Double)] = [:]
        if stoneHeight > 0 {
            var settings = ReaderSettings(); settings.stoneHeight = stoneHeight
            let reader = IntersectionReader(geometry: BoardGeometry(calibration: calibration)!, settings: settings)
            let blank = GrayImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height))
            for i in stones.keys { shifts[i] = reader.stoneShift(at: i, in: blank) }
        }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let offsets = [-0.25, 0.25]
        for y in 0..<height {
            for x in 0..<width {
                var v = 0.0
                for oy in offsets {
                    for ox in offsets {
                        let b = toBoard.apply(Point(x: Double(x) + ox, y: Double(y) + oy))
                        v += value(atBoard: b, shifts: shifts)
                    }
                }
                v = v / 4 * lighting(Double(x), Double(y))
                pixels[y * width + x] = UInt8(min(max(v, 0), 255))
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    private func value(atBoard b: Point, shifts: [Intersection: (Double, Double)]) -> Double {
        let n = Double(lines - 1)
        // Outside the wood (beyond one spacing past the grid): dark table.
        if b.x < -1 || b.y < -1 || b.x > n + 1 || b.y > n + 1 { return 60 }
        // A stone covers at most the cells around its (possibly lifted) centre.
        for row in Int((b.y - 1).rounded(.down))...Int((b.y + 1).rounded(.up)) {
            for col in Int((b.x - 1).rounded(.down))...Int((b.x + 1).rounded(.up)) {
                let i = Intersection(col: col, row: row)
                guard let stone = stones[i] else { continue }
                let shift = shifts[i] ?? (0, 0)
                let dx = b.x - (Double(col) + shift.0), dy = b.y - (Double(row) + shift.1)
                if dx * dx + dy * dy <= stoneRadius * stoneRadius { return stone == .black ? black : white }
            }
        }
        let onGrid = b.x >= -lineWidth && b.y >= -lineWidth && b.x <= n + lineWidth && b.y <= n + lineWidth
        if onGrid {
            let fx = abs(b.x - b.x.rounded()), fy = abs(b.y - b.y.rounded())
            if fx <= lineWidth / 2 || fy <= lineWidth / 2 { return lineDarkness }
        }
        return wood
    }
}
