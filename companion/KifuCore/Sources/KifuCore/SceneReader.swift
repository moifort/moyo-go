import Foundation

/// Reads the board by analysis by synthesis: every stone is an ellipsoid
/// standing on its intersection, seen through the camera recovered from the calibration; each
/// pixel shows the nearest object along its ray. A position is scored by how well the image it
/// predicts matches the photo, and the reading is the position that scores best. A stone hidden
/// behind another needs no special case: only its visible part is predicted.
public struct SceneSettings: Sendable, Equatable {
    /// Stone radius and thickness, in line spacings across the board.
    public var stoneRadius = 0.44
    public var stoneHeight = 0.40
    /// The image is reduced so that the smallest spacing is about this many pixels.
    public var targetSpacing = 10.0
    /// Cost of a stone, against a pixel cost of about 1 for a residual of one deviation.
    public var stonePrior = 8.0
    /// Residuals are truncated at this many deviations, so shadows and glints are not decisive.
    public var clip = 2.5
    /// How far past the outer lines, in spacings, the wood is modelled.
    public var margin = 0.55
    /// Half width of a grid line on the board, in spacings.
    public var lineHalfWidth = 0.06
    public var sweeps = 8
    public var rounds = 4
    /// An intersection whose best alternative costs less than this more is reported unsure.
    public var unsureBelow = 4.0
    /// ... plus this much per pixel of the stone's silhouette on its intersection.
    public var unsurePerPixel = 0.1
    /// Wood map cells per line spacing: fine enough to follow the edge of a patch of sunlight.
    public var woodCells = 2
    /// Wood in a cast shadow: this fraction of the wood, at this extra cost per pixel, so that a
    /// shadow never needs a black stone to be explained.
    public var shadowRatio = 0.5
    public var shadowCost = 0.5
    /// Stones sit this far, in spacings, from their intersection along the rows (+ is down the image).
    public var offset = 0.0
    /// A stone may sit this far off its intersection, in spacings, along either axis: players
    /// nudge stones, and a tight group pushes them apart.
    public var jitter = 0.2
    /// Cost of a stone per pixel of its unhidden silhouette: a stone has to explain its pixels
    /// clearly better than the wood, not just a little, or textured wood in sunlight passes for one.
    public var areaPrior = 0.3
    /// Cost of a stone off its intersection.
    public var jitterPrior = 2.0

    public init() {}
}

public struct SceneReading: Sendable {
    public var position: Position
    /// Extra cost of the best alternative at each intersection: how sure the reading is.
    public var margins: [Intersection: Double]
    public var unsure: Set<Intersection>
}

public final class SceneReader {
    public let settings: SceneSettings
    let lines: Int
    let scale: Int
    let width: Int, height: Int
    let camera: BoardGeometry.Camera?
    let geometry: BoardGeometry

    // Per sampled pixel.
    var intensity: [Float] = []
    var boardX: [Float] = [], boardY: [Float] = []
    var onLine: [Bool] = []
    var onBoard: [Bool] = []
    var pixelIndex: [Int32] = []      // linear index in the reduced image
    var hitStart: [Int32] = [], hitCount: [UInt8] = []
    // Hits, sorted by depth within a pixel.
    var hitStone: [Int16] = [], hitNormal: [Float] = [], hitWeight: [Float] = []
    // Per intersection: the sampled pixels its stone would cover if nothing were in front.
    var footprint: [[Int32]] = []
    /// Per stone variant: pixels of its silhouette on the board that no other intersection's stone can hide.
    var area: [Float] = []
    /// Intersections from the nearest to the farthest.
    var order: [Int] = []

    // Appearance.
    var wood: [Float] = []            // expected wood intensity per pixel
    var lineRatio: Float = 0.6
    /// Median of the whole board region, stones included: a reference no state can bias.
    var boardMedian: Float = 128
    var sigmaWood: Float = 12
    var blackMean: [Float] = [40, 40, 40, 40], sigmaBlack: Float = 18
    var whiteMean: [Float] = [220, 220, 220, 220], sigmaWhite: Float = 18
    static let normalBins = 4

    /// Per intersection: 0 empty, else 1 + (colour - 1) · variants + variant, colour 1 black, 2 white.
    var state: [UInt8] = []
    /// Where a stone may sit: on its intersection, or nudged along one axis.
    static let variants: [(Double, Double)] = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]
    static var variantCount: Int { variants.count }
    @inline(__always) static func colour(_ code: UInt8) -> UInt8 { code == 0 ? 0 : 1 + (code - 1) / UInt8(variantCount) }
    @inline(__always) static func variant(_ code: UInt8) -> Int { Int(code - 1) % variantCount }
    static func code(colour: UInt8, variant: Int) -> UInt8 { colour == 0 ? 0 : 1 + (colour - 1) * UInt8(variantCount) + UInt8(variant) }
    /// Every state an intersection can take.
    static let codes: [UInt8] = [0] + (1...2).flatMap { c in (0..<variantCount).map { code(colour: UInt8(c), variant: $0) } }
    /// Is the hit of stone variant `v` showing under the current state?
    @inline(__always) private func active(_ v: Int) -> UInt8 {
        let code = state[v / Self.variantCount]
        return code != 0 && Self.variant(code) == v % Self.variantCount ? Self.colour(code) : 0
    }
    private var stamp: [Int32] = []
    private var stampValue: Int32 = 0

    let lens: Lens

    /// `calibration` holds undistorted corners when `k1` is not zero.
    public convenience init?(image full: GrayImage, calibration: Calibration, k1: Double = 0, settings: SceneSettings = SceneSettings()) {
        self.init(calibration: calibration, imageWidth: full.width, imageHeight: full.height, k1: k1, settings: settings)
        load(full)
    }

    /// Renders the board for frames of the given size, once per calibration: every frame then
    /// only samples its pixels.
    ///
    /// `focal`, in pixels of the full frame, is the one an earlier reader found at calibration
    /// (`focal` of that reader): a grid refitted during the game must not change the lens.
    public init?(calibration: Calibration, imageWidth: Int, imageHeight: Int, k1: Double = 0, focal: Double? = nil, settings: SceneSettings = SceneSettings()) {
        self.settings = settings
        lines = calibration.lines
        guard let fullGeometry = BoardGeometry(calibration: calibration) else { return nil }
        let f = max(1, Int(fullGeometry.minSpacing / settings.targetSpacing))
        scale = f
        width = imageWidth / f; height = imageHeight / f
        lens = Lens(k1: k1, width: width, height: height)
        let corners = calibration.corners.map { Point(x: ($0.x + 0.5) / Double(f) - 0.5, y: ($0.y + 0.5) / Double(f) - 0.5) }
        guard let g = BoardGeometry(calibration: Calibration(lines: lines, corners: corners)) else { return nil }
        geometry = g
        camera = g.camera(imageWidth: width, imageHeight: height, focal: focal.map { $0 / Double(f) })
        build()
        state = [UInt8](repeating: 0, count: lines * lines)
        stamp = [Int32](repeating: 0, count: intensity.count)
    }

    /// The lens focal in pixels of the full frame, nil when the corners gave no camera.
    public var focal: Double? { camera.map { $0.focal * Double(scale) } }

    /// Samples `full`, a frame of the size the reader was built for.
    public func load(_ full: GrayImage) {
        let image = Self.reduce(full, by: scale)
        precondition(image.width == width && image.height == height, "frame size changed")
        image.pixels.withUnsafeBufferPointer { px in
            for p in 0..<intensity.count { intensity[p] = Float(px[Int(pixelIndex[p])]) }
        }
        boardMedian = Self.median(zip(intensity, onBoard).filter { $0.1 }.map { $0.0 })
    }

    static func reduce(_ image: GrayImage, by f: Int) -> GrayImage {
        guard f > 1 else { return image }
        let w = image.width / f, h = image.height / f
        var out = [UInt8](repeating: 0, count: w * h)
        image.pixels.withUnsafeBufferPointer { src in
            for y in 0..<h {
                for x in 0..<w {
                    var sum = 0
                    for dy in 0..<f {
                        let row = (y * f + dy) * image.width + x * f
                        for dx in 0..<f { sum += Int(src[row + dx]) }
                    }
                    out[y * w + x] = UInt8(sum / (f * f))
                }
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }

    // MARK: Rays

    struct Ray { var ox, oy, oz, dx, dy, dz: Double }

    private var inverse: [Double] = []   // M⁻¹, row-major
    private var centre: (Double, Double, Double) = (0, 0, 0)

    private func prepareRays() {
        guard let c = camera else { return }
        // Camera coordinates are M·X + t with M = [r1 r2 r3].
        let m = [c.r[0][0], c.r[1][0], c.r[2][0],
                 c.r[0][1], c.r[1][1], c.r[2][1],
                 c.r[0][2], c.r[1][2], c.r[2][2]]
        let det = m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6])
        let inv = [
            (m[4] * m[8] - m[5] * m[7]) / det, (m[2] * m[7] - m[1] * m[8]) / det, (m[1] * m[5] - m[2] * m[4]) / det,
            (m[5] * m[6] - m[3] * m[8]) / det, (m[0] * m[8] - m[2] * m[6]) / det, (m[2] * m[3] - m[0] * m[5]) / det,
            (m[3] * m[7] - m[4] * m[6]) / det, (m[1] * m[6] - m[0] * m[7]) / det, (m[0] * m[4] - m[1] * m[3]) / det,
        ]
        inverse = inv
        let t = c.t
        centre = (-(inv[0] * t[0] + inv[1] * t[1] + inv[2] * t[2]),
                  -(inv[3] * t[0] + inv[4] * t[1] + inv[5] * t[2]),
                  -(inv[6] * t[0] + inv[7] * t[1] + inv[8] * t[2]))
    }

    private func ray(_ u: Double, _ v: Double) -> Ray {
        let c = camera!
        let d = [(u - c.k[2]) / c.focal, (v - c.k[5]) / c.focal, 1.0]
        let i = inverse
        return Ray(ox: centre.0, oy: centre.1, oz: centre.2,
                   dx: i[0] * d[0] + i[1] * d[1] + i[2] * d[2],
                   dy: i[3] * d[0] + i[4] * d[1] + i[5] * d[2],
                   dz: i[6] * d[0] + i[7] * d[1] + i[8] * d[2])
    }

    /// Depth along the ray, the vertical part of the surface normal where the ray first meets
    /// the stone standing on (px, py), and how far inside the silhouette the ray passes, from 0
    /// on its outline to 1 a fifth of the radius inside: the outline of a real stone does not
    /// follow the ellipsoid to the pixel.
    private func hit(_ r: Ray, _ px: Double, _ py: Double) -> (Double, Double, Double)? {
        let a = settings.stoneRadius, b = settings.stoneHeight / 2
        let ox = (r.ox - px) / a, oy = (r.oy - py - settings.offset) / a, oz = (r.oz - b) / b
        let dx = r.dx / a, dy = r.dy / a, dz = r.dz / b
        let qa = dx * dx + dy * dy + dz * dz
        let qb = 2 * (ox * dx + oy * dy + oz * dz)
        let qc = ox * ox + oy * oy + oz * oz - 1
        let disc = qb * qb - 4 * qa * qc
        guard disc >= 0 else { return nil }
        let s = (-qb - disc.squareRoot()) / (2 * qa)
        guard s > 0 else { return nil }
        let hx = ox + s * dx, hy = oy + s * dy, hz = oz + s * dz
        // Gradient of the unit sphere in the scaled frame, mapped back.
        let nx = hx / a, ny = hy / a, nz = hz / b
        let norm = (nx * nx + ny * ny + nz * nz).squareRoot()
        let closest = (qc + 1) - qb * qb / (4 * qa)
        return (s, nz / norm, min(1, max(0, (1 - closest) / 0.36)))
    }

    // MARK: Sampling

    private func build() {
        prepareRays()
        let n = Double(lines - 1), m = settings.margin
        let count = lines * lines
        // Image boxes of every stone and of the board.
        var boxes: [(Int, Int, Int, Int)] = []
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        func include(_ p: Point) {
            minX = min(minX, Int(p.x.rounded(.down))); maxX = max(maxX, Int(p.x.rounded(.up)))
            minY = min(minY, Int(p.y.rounded(.down))); maxY = max(maxY, Int(p.y.rounded(.up)))
        }
        let V = Self.variantCount
        for v in 0..<(count * V) {
            let k = v / V, o = Self.variants[v % V]
            let px = Double(k % lines) + o.0 * settings.jitter, py = Double(k / lines) + o.1 * settings.jitter
            var bx0 = Int.max, by0 = Int.max, bx1 = Int.min, by1 = Int.min
            let a = settings.stoneRadius
            for zx in [-a, a] {
                for zy in [-a, a] {
                    for z in [0.0, settings.stoneHeight] {
                        let p = lens.distort(camera?.project(Point(x: px + zx, y: py + zy + settings.offset), height: z) ?? geometry.imagePoint(boardX: px + zx, boardY: py + zy))
                        bx0 = min(bx0, Int(p.x.rounded(.down))); bx1 = max(bx1, Int(p.x.rounded(.up)))
                        by0 = min(by0, Int(p.y.rounded(.down))); by1 = max(by1, Int(p.y.rounded(.up)))
                        include(p)
                    }
                }
            }
            boxes.append((bx0, by0, bx1, by1))
        }
        for (bx, by) in [(-m, -m), (n + m, -m), (n + m, n + m), (-m, n + m)] { include(lens.distort(geometry.imagePoint(boardX: bx, boardY: by))) }
        minX = max(minX, 0); minY = max(minY, 0); maxX = min(maxX, width - 1); maxY = min(maxY, height - 1)

        // Bucket the stone boxes so each pixel tests only the stones that may cover it.
        let cell = 16
        let bw = (maxX - minX) / cell + 1, bh = (maxY - minY) / cell + 1
        var buckets = [[Int16]](repeating: [], count: bw * bh)
        for (k, b) in boxes.enumerated() {
            let x0 = max(0, (b.0 - minX) / cell), x1 = min(bw - 1, (b.2 - minX) / cell)
            let y0 = max(0, (b.1 - minY) / cell), y1 = min(bh - 1, (b.3 - minY) / cell)
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 { buckets[y * bw + x].append(Int16(k)) } }
        }

        footprint = [[Int32]](repeating: [], count: count)
        var lastPixel = [Int32](repeating: -1, count: count)
        for y in minY...maxY {
            for x in minX...maxX {
                let undistorted = lens.undistort(Point(x: Double(x), y: Double(y)))
                let u = undistorted.x, v = undistorted.y
                var hits: [(Double, Int16, Double, Double)] = []
                let bp: Point
                if camera != nil {
                    let r = ray(u, v)
                    guard r.dz < 0 else { continue }
                    let s = -r.oz / r.dz
                    bp = Point(x: r.ox + s * r.dx, y: r.oy + s * r.dy)
                    for k in buckets[((y - minY) / cell) * bw + (x - minX) / cell] {
                        let i = Int(k) / V, o = Self.variants[Int(k) % V]
                        let px = Double(i % lines) + o.0 * settings.jitter, py = Double(i / lines) + o.1 * settings.jitter
                        if let h = hit(r, px, py) { hits.append((h.0, k, h.1, h.2)) }
                    }
                } else {
                    bp = geometry.toBoard.apply(Point(x: u, y: v))
                    for k in buckets[((y - minY) / cell) * bw + (x - minX) / cell] {
                        let i = Int(k) / V, o = Self.variants[Int(k) % V]
                        let dx = bp.x - Double(i % lines) - o.0 * settings.jitter, dy = bp.y - Double(i / lines) - o.1 * settings.jitter
                        let d2 = (dx * dx + dy * dy) / (settings.stoneRadius * settings.stoneRadius)
                        if d2 < 1 { hits.append((0, k, 1, min(1, (1 - d2) / 0.36))) }
                    }
                }
                let inside = bp.x >= -m && bp.y >= -m && bp.x <= n + m && bp.y <= n + m
                guard inside || !hits.isEmpty else { continue }
                hits.sort { $0.0 < $1.0 }
                let index = Int32(intensity.count)
                intensity.append(0)
                boardX.append(Float(bp.x)); boardY.append(Float(bp.y))
                onBoard.append(inside)
                let fx = abs(bp.x - bp.x.rounded()), fy = abs(bp.y - bp.y.rounded())
                let w = settings.lineHalfWidth
                let line = (fx < w && bp.y >= -w && bp.y <= n + w) || (fy < w && bp.x >= -w && bp.x <= n + w)
                onLine.append(line)
                pixelIndex.append(Int32(y * width + x))
                hitStart.append(Int32(hitStone.count)); hitCount.append(UInt8(min(hits.count, 255)))
                for h in hits {
                    hitStone.append(h.1); hitNormal.append(Float(h.2)); hitWeight.append(Float(h.3))
                    let k = Int(h.1) / V
                    if lastPixel[k] != index { footprint[k].append(index); lastPixel[k] = index }
                }
            }
        }
        // Nearest first: the stones that nothing hides are settled before the ones behind them.
        let depth: [Double] = (0..<count).map { k in
            let px = Double(k % lines), py = Double(k / lines)
            if camera != nil {
                return (px - centre.0) * (px - centre.0) + (py - centre.1) * (py - centre.1)
            }
            return 0
        }
        order = (0..<count).sorted { depth[$0] < depth[$1] }
        area = [Float](repeating: 0, count: count * V)
        for p in 0..<intensity.count where hitCount[p] > 0 && onBoard[p] {
            let s = Int(hitStart[p])
            let first = Int(hitStone[s]) / V
            for h in s..<(s + Int(hitCount[p])) {
                let v = Int(hitStone[h])
                guard v / V == first else { break }
                area[v] += 1
            }
        }
        wood = [Float](repeating: 128, count: intensity.count)
    }

    // MARK: Appearance

    /// What pixel `p` shows under the current state: 0 wood, 1 black, 2 white, with the normal.
    @inline(__always) private func label(_ p: Int) -> (UInt8, Float) {
        let s = Int(hitStart[p])
        for h in s..<(s + Int(hitCount[p])) {
            let st = active(Int(hitStone[h]))
            if st != 0 { return (st, hitNormal[h]) }
        }
        return (0, 0)
    }

    /// True when the pixel lies well inside the silhouette that `label` gives it.
    @inline(__always) private func certain(_ p: Int) -> Bool {
        let s = Int(hitStart[p])
        for h in s..<(s + Int(hitCount[p])) where active(Int(hitStone[h])) != 0 { return hitWeight[h] >= 1 }
        return true
    }

    /// Cost of pixel `p` under the current state. Near a stone's outline the cost blends the
    /// stone with whatever lies behind it, by how far inside the outline the ray passes.
    @inline(__always) private func pixelCost(_ p: Int) -> Float {
        let s = Int(hitStart[p])
        var remaining: Float = 1, total: Float = 0
        for h in s..<(s + Int(hitCount[p])) {
            let st = active(Int(hitStone[h]))
            guard st != 0 else { continue }
            let w = hitWeight[h]
            total += remaining * w * (st == 1 ? blackCost[h] : whiteCost[h])
            remaining *= 1 - w
            if remaining < 0.01 { return total }
        }
        return total + remaining * woodCost[p]
    }

    /// Costs of every pixel as wood and of every hit as either colour, for the current appearance.
    private var woodCost: [Float] = [], blackCost: [Float] = [], whiteCost: [Float] = []
    private func refreshCosts() {
        woodCost = (0..<intensity.count).map { cost($0, 0, 0) }
        blackCost = [Float](repeating: 0, count: hitStone.count)
        whiteCost = [Float](repeating: 0, count: hitStone.count)
        for p in 0..<intensity.count {
            let s = Int(hitStart[p])
            for h in s..<(s + Int(hitCount[p])) {
                blackCost[h] = cost(p, 1, hitNormal[h]); whiteCost[h] = cost(p, 2, hitNormal[h])
            }
        }
    }

    @inline(__always) private func bin(_ nz: Float) -> Int { min(Self.normalBins - 1, max(0, Int(nz * Float(Self.normalBins)))) }

    @inline(__always) private func cost(_ p: Int, _ l: UInt8, _ nz: Float) -> Float {
        let mean: Float, sigma: Float
        switch l {
        case 0:
            // Off the board the photo shows the table or the room: no evidence either way.
            if !onBoard[p] { return 0 }
            let lit = onLine[p] ? wood[p] * lineRatio : wood[p]
            let c = Float(settings.clip)
            let z = (intensity[p] - lit) / sigmaWood
            // A cast shadow is anywhere between `shadowRatio` and nearly lit wood.
            let low = lit * Float(settings.shadowRatio), high = lit * 0.9
            let gap = intensity[p] < low ? low - intensity[p] : intensity[p] > high ? intensity[p] - high : 0
            let zs = gap / sigmaWood
            return min(0.5 * min(z * z, c * c), 0.5 * min(zs * zs, c * c) + Float(settings.shadowCost))
        case 1:
            guard onBoard[p] else { return 0 }
            mean = min(blackMean[bin(nz)], 0.45 * boardMedian); sigma = sigmaBlack
        default:
            guard onBoard[p] else { return 0 }
            mean = max(whiteMean[bin(nz)], wood[p] + 0.2 * (255 - wood[p])); sigma = sigmaWhite
        }
        let z = (intensity[p] - mean) / sigma
        let c = Float(settings.clip)
        return 0.5 * min(z * z, c * c)
    }

    /// Re-estimates wood, line darkening and stone colours from the pixels the current state
    /// attributes to each.
    public var timings: [String: Double] = [:]
    func timed<T>(_ name: String, _ f: () -> T) -> T {
        let t = Date(); let r = f(); timings[name, default: 0] += -t.timeIntervalSinceNow; return r
    }

    func estimateAppearance(colours: Bool, fine: Bool = false) { timed("estimate") { estimate(colours: colours, fine: fine); refreshCosts() } }

    private func estimate(colours: Bool, fine: Bool) {
        let n = lines - 1
        let m = settings.margin
        // Wood: median per board cell, centred on half-integers from -0.5 to n + 0.5.
        let perSpacing = fine ? settings.woodCells : 1
        let cells = (n + 2) * perSpacing
        let rate = Double(perSpacing)
        var hist = [[Int32]](repeating: [Int32](repeating: 0, count: 256), count: cells * cells)
        var linePairs: [Float] = []
        var labels = [UInt8](repeating: 0, count: intensity.count)
        var normals = [Float](repeating: 0, count: intensity.count)
        for p in 0..<intensity.count {
            let (l, nz) = label(p); labels[p] = l; normals[p] = nz
            // Far darker than the board can only be a stone or a deep shadow, never the wood itself.
            guard l == 0, onBoard[p], !onLine[p], intensity[p] > 0.55 * boardMedian else { continue }
            let cx = min(cells - 1, max(0, Int(((Double(boardX[p]) + 1) * rate).rounded(.down))))
            let cy = min(cells - 1, max(0, Int(((Double(boardY[p]) + 1) * rate).rounded(.down))))
            hist[cy * cells + cx][Int(intensity[p])] += 1
        }
        _ = m
        var value = [Float?](repeating: nil, count: cells * cells)
        for c in 0..<(cells * cells) {
            let total = hist[c].reduce(0, +)
            guard total >= 8 else { continue }
            var acc: Int32 = 0
            for v in 0..<256 { acc += hist[c][v]; if acc * 2 >= total { value[c] = Float(v); break } }
        }
        // Fill the cells that stones cover from their neighbours.
        for _ in 0..<cells {
            guard value.contains(where: { $0 == nil }) else { break }
            var next = value
            for cy in 0..<cells {
                for cx in 0..<cells where value[cy * cells + cx] == nil {
                    var sum: Float = 0, k: Float = 0
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let x = cx + dx, y = cy + dy
                        guard x >= 0, y >= 0, x < cells, y < cells, let v = value[y * cells + x] else { continue }
                        sum += v; k += 1
                    }
                    if k > 0 { next[cy * cells + cx] = sum / k }
                }
            }
            value = next
        }
        let grid = value.map { $0 ?? 128 }
        // Bilinear between cell centres, at (cx - 0.5, cy - 0.5) in board units.
        for p in 0..<intensity.count {
            let x = min(max((Double(boardX[p]) + 1) * rate - 0.5, 0), Double(cells - 1))
            let y = min(max((Double(boardY[p]) + 1) * rate - 0.5, 0), Double(cells - 1))
            let x0 = min(Int(x), cells - 2), y0 = min(Int(y), cells - 2)
            let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
            let a = grid[y0 * cells + x0], b = grid[y0 * cells + x0 + 1]
            let c = grid[(y0 + 1) * cells + x0], d = grid[(y0 + 1) * cells + x0 + 1]
            wood[p] = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
            if labels[p] == 0, onBoard[p], onLine[p] { linePairs.append(intensity[p] / max(wood[p], 1)) }
        }
        if linePairs.count > 50 { lineRatio = min(1, max(0.4, Self.median(linePairs.map { $0 * 100 }) / 100)) }
        var residuals: [Float] = []
        for p in 0..<intensity.count where labels[p] == 0 && onBoard[p] && !onLine[p] { residuals.append(abs(intensity[p] - wood[p])) }
        if residuals.count > 50 { sigmaWood = min(30, max(10, 1.4826 * Self.median(residuals))) }

        let woodMedian = Self.median(grid)
        guard colours else {
            blackMean = [Float](repeating: min(70, 0.3 * woodMedian), count: Self.normalBins)
            whiteMean = [Float](repeating: woodMedian + 0.55 * (255 - woodMedian), count: Self.normalBins)
            return
        }
        for colour in [UInt8(1), 2] {
            var byBin = [[Float]](repeating: [], count: Self.normalBins)
            for p in 0..<intensity.count where labels[p] == colour && certain(p) { byBin[bin(normals[p])].append(intensity[p]) }
            let all = byBin.flatMap { $0 }
            guard all.count >= 40 else { continue }
            let overall = Self.median(all)
            let means = byBin.map { $0.count >= 20 ? Self.median($0) : overall }
            let spread = min(colour == 1 ? 20 : 25, max(12, 1.4826 * Self.median(all.map { abs($0 - overall) })))
            // A colour learned from wood or shadow would explain the wood with stones.
            if colour == 1 { blackMean = means.map { min($0, 0.45 * woodMedian) }; sigmaBlack = spread }
            else { whiteMean = means.map { max($0, woodMedian + 0.15 * (255 - woodMedian)) }; sigmaWhite = spread }
        }
    }

    /// Median to a quarter of a grey level, by histogram: the arrays run to half a million values.
    static func median(_ v: [Float]) -> Float {
        guard !v.isEmpty else { return 0 }
        guard v.count > 256 else { let s = v.sorted(); return s[s.count / 2] }
        let bins = 1024
        var hist = [Int32](repeating: 0, count: bins + 1)
        for x in v { hist[min(bins, max(0, Int(x * 4)))] += 1 }
        var acc: Int32 = 0
        let half = Int32(v.count / 2)
        for (i, c) in hist.enumerated() { acc += c; if acc > half { return Float(i) / 4 } }
        return Float(bins) / 4
    }

    // MARK: Search

    /// Cost change of setting each intersection of `changes` to its new state.
    func delta(_ changes: [(Int, UInt8)]) -> Float {
        stampValue += 1
        var touched: [Int32] = []
        for (k, _) in changes {
            for p in footprint[k] where stamp[Int(p)] != stampValue {
                stamp[Int(p)] = stampValue; touched.append(p)
            }
        }
        var before: Float = 0
        for p in touched { before += pixelCost(Int(p)) }
        var saved: [UInt8] = []
        var prior: Float = 0
        for (k, s) in changes {
            saved.append(state[k])
            prior += codePrior(s, at: k) - codePrior(state[k], at: k)
            state[k] = s
        }
        var after: Float = 0
        for p in touched { after += pixelCost(Int(p)) }
        for (i, (k, _)) in changes.enumerated() { state[k] = saved[i] }
        return after - before + prior
    }

    /// Cost change of each state of `codes` at the single intersection `k`; the pixels it
    /// covers are costed once for the current state.
    func deltas(_ k: Int, _ codes: [UInt8]) -> [Float] {
        let pixels = footprint[k]
        var before: Float = 0
        for p in pixels { before += pixelCost(Int(p)) }
        let saved = state[k]
        let prior = codePrior(saved, at: k)
        var out: [Float] = []
        for code in codes {
            state[k] = code
            var after: Float = 0
            for p in pixels { after += pixelCost(Int(p)) }
            out.append(after - before + codePrior(code, at: k) - prior)
        }
        state[k] = saved
        return out
    }

    private func codePrior(_ code: UInt8, at k: Int) -> Float {
        guard code != 0 else { return 0 }
        let v = k * Self.variantCount + Self.variant(code)
        return Float(settings.stonePrior) + Float(settings.areaPrior) * area[v] + (Self.variant(code) == 0 ? 0 : Float(settings.jitterPrior))
    }

    private func neighbours(_ k: Int) -> [Int] {
        let c = k % lines, r = k / lines
        var out: [Int] = []
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)] {
            let x = c + dx, y = r + dy
            if x >= 0, y >= 0, x < lines, y < lines { out.append(y * lines + x) }
        }
        return out
    }

    /// Lowers the cost one intersection at a time, then by moving stones to a neighbour.
    /// The states worth trying at `k`: empty and both colours on the intersection, plus the
    /// nudged variants of the colour already there.
    private func candidates(_ k: Int) -> [UInt8] {
        let colour = Self.colour(state[k])
        var out: [UInt8] = [0, Self.code(colour: 1, variant: 0), Self.code(colour: 2, variant: 0)]
        if colour != 0 { out += (1..<Self.variantCount).map { Self.code(colour: colour, variant: $0) } }
        return out.filter { $0 != state[k] }
    }

    /// Lowers the cost one intersection at a time, then by moving stones to a neighbour. After
    /// the first sweep only the intersections next to a change are tried again.
    func optimise() { timed("optimise") { optimiseNow() } }

    private func optimiseNow() {
        var dirty = [Bool](repeating: true, count: lines * lines)
        func touch(_ k: Int) {
            let c = k % lines, r = k / lines
            for dy in -2...2 { for dx in -2...2 {
                let x = c + dx, y = r + dy
                if x >= 0, y >= 0, x < lines, y < lines { dirty[y * lines + x] = true }
            } }
        }
        for _ in 0..<settings.sweeps {
            var next = [Bool](repeating: false, count: lines * lines)
            swap(&dirty, &next)
            var changed = false
            for k in order where next[k] {
                var best: (Float, UInt8) = (-0.01, state[k])
                let codes = candidates(k)
                for (s, d) in zip(codes, deltas(k, codes)) where d < best.0 { best = (d, s) }
                if best.1 != state[k] { state[k] = best.1; changed = true; touch(k) }
            }
            for k in order where next[k] && state[k] != 0 {
                var best: (Float, Int) = (-0.01, -1)
                for j in neighbours(k) where state[j] == 0 {
                    let d = delta([(k, 0), (j, Self.code(colour: Self.colour(state[k]), variant: 0))])
                    if d < best.0 { best = (d, j) }
                }
                if best.1 >= 0 { state[best.1] = Self.code(colour: Self.colour(state[k]), variant: 0); state[k] = 0; changed = true; touch(k); touch(best.1) }
            }
            if !changed { break }
        }
    }

    /// Whether an image was read already: the next one starts from what it showed.
    private var warm = false

    /// Reads the image last loaded. A first reading starts from scratch, or from `previous`;
    /// the next ones start from `previous` with the appearance the last image left, which the
    /// last reading learned with every stone accounted for. A wood map learned before a new
    /// stone is found would follow that stone and absorb it.
    public func read(previous: Position?) -> SceneReading {
        let last = state
        if let previous {
            for i in previous.all {
                let k = i.row * lines + i.col
                let colour: UInt8 = previous[i] == .black ? 1 : previous[i] == .white ? 2 : 0
                // Keep where the stone was found sitting, when it is still the same stone.
                state[k] = Self.colour(last[k]) == colour ? last[k] : Self.code(colour: colour, variant: 0)
            }
        } else {
            state = [UInt8](repeating: 0, count: lines * lines)
        }
        let start = state
        if warm {
            timed("refresh") { refreshCosts() }
            optimise()
            estimateAppearance(colours: true, fine: true)
            optimise()
            // A move changes one intersection. More means the last image taught a wrong
            // appearance, a hand over the board most often: read this one afresh.
            let changed = (0..<(lines * lines)).filter { Self.colour(state[$0]) != Self.colour(start[$0]) }.count
            if changed > 2 { warm = false; state = start }
        }
        if !warm {
            estimateAppearance(colours: false)
            // A coarse wood map first: a fine one would follow the stones not yet found and absorb
            // them. Once they are found, a fine one follows the edge of a patch of sunlight.
            for _ in 0..<settings.rounds {
                optimise()
                estimateAppearance(colours: true)
            }
            optimise()
            estimateAppearance(colours: true, fine: true)
            optimise()
            warm = true
        }
        var position = Position(size: lines)
        var margins: [Intersection: Double] = [:]
        var unsure: Set<Intersection> = []
        for k in 0..<(lines * lines) {
            let i = Intersection(col: k % lines, row: k / lines)
            let colour = Self.colour(state[k])
            position[i] = colour == 1 ? .black : colour == 2 ? .white : .empty
            let others = Self.codes.filter { Self.colour($0) != colour }
            let margin = timed("margins") { deltas(k, others).min() ?? 0 }
            margins[i] = Double(margin)
            if Double(margin) < settings.unsureBelow + settings.unsurePerPixel * Double(area[k * Self.variantCount]) { unsure.insert(i) }
        }
        return SceneReading(position: position, margins: margins, unsure: unsure)
    }

    // MARK: Debug

    /// The predicted image of the current state, full size of the reduced image, 0 outside the samples.
    public func rendered() -> GrayImage {
        var out = [UInt8](repeating: 0, count: width * height)
        for p in 0..<intensity.count {
            let (l, nz) = label(p)
            let v: Float
            switch l {
            case 0: v = onBoard[p] ? (onLine[p] ? wood[p] * lineRatio : wood[p]) : 0
            case 1: v = blackMean[bin(nz)]
            default: v = whiteMean[bin(nz)]
            }
            out[Int(pixelIndex[p])] = UInt8(max(0, min(255, v)))
        }
        return GrayImage(width: width, height: height, pixels: out)
    }

    /// Label map: 0 outside, 1 wood, 2 black, 3 white; in reduced pixels.
    public func labelMap() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)
        for p in 0..<intensity.count { out[Int(pixelIndex[p])] = label(p).0 + 1 }
        return out
    }

    public var reducedSize: (Int, Int, Int) { (width, height, scale) }

    public func probe(_ i: Intersection) -> String {
        let k = i.row * lines + i.col
        let f = footprint[k]
        var visible = 0, sum: Float = 0, woodSum: Float = 0, inside = 0
        for p in f {
            let s = Int(hitStart[Int(p)])
            if Int(hitStone[s]) / Self.variantCount == k { visible += 1; sum += intensity[Int(p)]; woodSum += wood[Int(p)]; if onBoard[Int(p)] { inside += 1 } }
        }
        let d = [UInt8(0), Self.code(colour: 1, variant: 0), Self.code(colour: 2, variant: 0)].map { delta([(k, $0)]) }
        let at = lens.distort(geometry.imagePoint(boardX: Double(i.col), boardY: Double(i.row)))
        return String(format: "at %.0f,%.0f full px ", at.x * Double(scale), at.y * Double(scale)) + String(format: "%@ state %d footprint %d front %d (on board %d) mean %.0f wood %.0f; Δ empty %.1f black %.1f white %.1f",
                      i.description, state[k], f.count, visible, inside, sum / Float(max(visible, 1)), woodSum / Float(max(visible, 1)), d[0], d[1], d[2])
    }

    public var totalCost: Double {
        var sum: Float = 0
        for p in 0..<intensity.count { sum += pixelCost(p) }
        return Double(sum) + settings.stonePrior * Double(state.filter { $0 != 0 }.count)
    }

    public var cameraReport: String {
        guard let c = camera else { return "no camera" }
        let p0 = c.project(Point(x: 2, y: 17), height: 0), p1 = c.project(Point(x: 2, y: 17), height: 0.4)
        let g = geometry.imagePoint(boardX: 2, boardY: 17)
        let r = ray(p1.x, p1.y)
        let s = -r.oz / r.dz
        return String(format: "focal %.0f centre (%.2f, %.2f, %.2f); (2,17) h0 %.1f,%.1f homography %.1f,%.1f h0.4 %.1f,%.1f; ray back to board %.2f,%.2f", c.focal, centre.0, centre.1, centre.2, p0.x, p0.y, g.x, g.y, p1.x, p1.y, r.ox + s * r.dx, r.oy + s * r.dy)
    }

    public var appearance: String {
        String(format: "scale %d, %d px, wood σ %.0f line ×%.2f, black %@ σ %.0f, white %@ σ %.0f", scale, intensity.count, sigmaWood, lineRatio,
               blackMean.map { String(format: "%.0f", $0) }.joined(separator: "/"), sigmaBlack,
               whiteMean.map { String(format: "%.0f", $0) }.joined(separator: "/"), sigmaWhite)
    }
}

/// Radial lens distortion about the frame centre: a pinhole point p shows at
/// c + (p - c)(1 + k1 r²), with r measured in half diagonals.
public struct Lens: Sendable, Equatable {
    public var k1: Double
    public let cx: Double, cy: Double, radius: Double

    public init(k1: Double = 0, width: Int, height: Int) {
        self.k1 = k1
        cx = Double(width) / 2; cy = Double(height) / 2
        radius = (Double(width * width + height * height)).squareRoot() / 2
    }

    public func distort(_ p: Point) -> Point {
        let dx = (p.x - cx) / radius, dy = (p.y - cy) / radius
        let f = 1 + k1 * (dx * dx + dy * dy)
        return Point(x: cx + (p.x - cx) * f, y: cy + (p.y - cy) * f)
    }

    public func undistort(_ q: Point) -> Point {
        var p = q
        for _ in 0..<6 {
            let dx = (p.x - cx) / radius, dy = (p.y - cy) / radius
            let f = 1 + k1 * (dx * dx + dy * dy)
            p = Point(x: cx + (q.x - cx) / f, y: cy + (q.y - cy) / f)
        }
        return p
    }

    /// The same lens on an image reduced `f` times.
    public func reduced(by f: Int, width: Int, height: Int) -> Lens { Lens(k1: k1, width: width, height: height) }
}

extension SceneReader {
    /// Grid contrast with the lens: like `BoardGeometry.gridScore`, the darkness along every line
    /// minus the darkness a third of a spacing to either side.
    static func gridScore(_ corners: [Point], lens: Lens, lines: Int, in image: GrayImage, samples: Int = 40) -> Double {
        let n = Double(lines - 1)
        let src = [Point(x: 0, y: 0), Point(x: n, y: 0), Point(x: n, y: n), Point(x: 0, y: n)]
        guard let h = Homography(from: src, to: corners) else { return -.infinity }
        func darkness(_ x: Double, _ y: Double) -> Double {
            let p = lens.distort(h.apply(Point(x: x, y: y)))
            return 255 - image.sample(x: p.x, y: p.y)
        }
        let side = 0.33
        var sum = 0.0
        for k in 0..<lines {
            let t = Double(k)
            for s in 0..<samples {
                let u = n * (Double(s) + 0.5) / Double(samples)
                sum += darkness(t, u) - (darkness(t - side, u) + darkness(t + side, u)) / 2
                sum += darkness(u, t) - (darkness(u, t - side) + darkness(u, t + side)) / 2
            }
        }
        return sum / Double(2 * lines * samples)
    }

    /// Refits the grid and the lens, coarse to fine. Used by `kifu-tool eval --refine` only: the
    /// app reads well without the lens, and the tracker keeps the plain corners. On a reduced image the lines are
    /// wide smudges, so the score still rises a quarter of a cell away from them. Returns the
    /// undistorted corners and the lens, both for the full image.
    public static func fitGrid(_ corners: [Point], lines: Int, in image: GrayImage) -> ([Point], Lens) {
        var lens = Lens(width: image.width, height: image.height)
        var current = corners.map { lens.undistort($0) }
        for (f, radius) in [(4, 6.0), (2, 3.0), (1, 2.0)] {
            let small = reduce(image, by: f)
            let smallLens = Lens(k1: lens.k1, width: small.width, height: small.height)
            func toSmall(_ p: Point) -> Point { Point(x: (p.x + 0.5) / Double(f) - 0.5, y: (p.y + 0.5) / Double(f) - 0.5) }
            var c = current.map(toSmall)
            var k1 = smallLens.k1
            let origin = c
            func score(_ c: [Point], _ k: Double) -> Double {
                gridScore(c, lens: Lens(k1: k, width: small.width, height: small.height), lines: lines, in: small)
            }
            var best = score(c, k1)
            var step = radius
            var kStep = 0.02
            while step >= 0.25 {
                var improved = true
                while improved {
                    improved = false
                    for dk in [kStep, -kStep] {
                        let s = score(c, k1 + dk)
                        if s > best + 1e-9 { best = s; k1 += dk; improved = true }
                    }
                    for (dx, dy) in [(step, 0.0), (-step, 0.0), (0.0, step), (0.0, -step)] {
                        for moved in [[0], [1], [2], [3], [0, 1, 2, 3]] {
                            var candidate = c
                            for k in moved { candidate[k] = Point(x: c[k].x + dx, y: c[k].y + dy) }
                            guard moved.allSatisfy({ abs(candidate[$0].x - origin[$0].x) <= radius * 2 && abs(candidate[$0].y - origin[$0].y) <= radius * 2 }) else { continue }
                            let s = score(candidate, k1)
                            if s > best + 1e-9 { best = s; c = candidate; improved = true }
                        }
                    }
                }
                step /= 2; kStep /= 2
            }
            current = c.map { Point(x: ($0.x + 0.5) * Double(f) - 0.5, y: ($0.y + 0.5) * Double(f) - 0.5) }
            lens = Lens(k1: k1, width: image.width, height: image.height)
        }
        return (current, lens)
    }

    public static func score(_ corners: [Point], lens: Lens, lines: Int, in image: GrayImage) -> Double {
        gridScore(corners, lens: lens, lines: lines, in: image)
    }
}

extension SceneReader: BoardReader {
    /// What the recorder sees: the stones of the best explanation, the intersections where
    /// another one is nearly as good left unreadable.
    public func read(_ image: GrayImage, previous: Position?) -> Readings {
        timed("load") { load(image) }
        let reading = timed("read") { read(previous: previous) }
        return Readings(position: reading.position, unreadable: reading.unsure)
    }
}
