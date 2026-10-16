import Foundation

/// Finds the exact grid from four rough corner taps.
///
/// The rough quad gives the perspective. The region around it is rectified to a square where
/// the lines are nearly vertical and horizontal; in each direction a comb of `lines` regularly
/// spaced teeth (with a quadratic term for the residual perspective) is fitted to a line-contrast
/// profile, in three bands so that a slight rotation is followed. The outer lines of both
/// directions give the corners, mapped back into the image.
public enum GridDetector {
    /// Spacings of context kept around the rough quad: taps may be this far off.
    static let margin = 1.5
    /// Rectified pixels per line spacing.
    static let cell = 40
    static let bands = 3
    /// Mean line contrast (gray levels) below which there is no grid.
    static let minimumContrast = 1.0
    /// Cost of a tooth placed where no perpendicular line crosses.
    static let unsupportedToothPenalty = 10.0
    /// Diagnostic sink, set by tools.
    nonisolated(unsafe) public static var trace: ((String) -> Void)?

    /// Passes of rectify-and-fit: each one removes most of the residual perspective of the previous.
    static let passes = 3

    public static func detect(roughCorners: [Point], lines: Int, in image: GrayImage) -> [Point]? {
        var corners = roughCorners
        for pass in 0..<passes {
            trace?("pass \(pass) from " + corners.map { String(format: "%.1f,%.1f", $0.x, $0.y) }.joined(separator: " "))
            // After the first pass the grid is expected right where the rectification puts it.
            guard let next = singlePass(roughCorners: corners, lines: lines, in: image, seeded: pass > 0) else {
                return pass == 0 ? nil : corners
            }
            corners = next
        }
        return BoardGeometry.fitCorners(corners, lines: lines, in: image, radius: 3)
    }

    static func singlePass(roughCorners: [Point], lines: Int, in image: GrayImage, seeded: Bool = false) -> [Point]? {
        guard roughCorners.count == 4, lines >= 2 else { return nil }
        let n = Double(lines - 1)
        let square = [Point(x: 0, y: 0), Point(x: n, y: 0), Point(x: n, y: n), Point(x: 0, y: n)]
        guard let rough = Homography(from: square, to: roughCorners) else { return nil }

        let span = n + 2 * margin
        let size = Int((span * Double(cell)).rounded())
        func board(_ u: Double, _ v: Double) -> Point { Point(x: u / Double(cell) - margin, y: v / Double(cell) - margin) }
        var pixels = [UInt8](repeating: 0, count: size * size)
        for v in 0..<size {
            for u in 0..<size {
                let b = board(Double(u), Double(v))
                let p = rough.apply(b)
                pixels[v * size + u] = UInt8(min(max(image.sample(x: p.x, y: p.y), 0), 255))
            }
        }
        let rect = GrayImage(width: size, height: size, pixels: pixels)

        let seed = seeded ? Comb(first: margin * Double(cell), last: (margin + n) * Double(cell), teeth: lines, perspective: 0) : nil
        guard let vertical = outerLines(in: rect, vertical: true, lines: lines, seed: seed),
              let horizontal = outerLines(in: rect, vertical: false, lines: lines, seed: seed) else { return nil }

        // Rectified corners: intersections of outer vertical lines (x = a + b·y) and horizontal ones (y = c + d·x).
        func intersect(_ xl: (a: Double, b: Double), _ yl: (a: Double, b: Double)) -> Point {
            let x = (xl.a + xl.b * yl.a) / (1 - xl.b * yl.b)
            return Point(x: x, y: yl.a + yl.b * x)
        }
        let rectified = [intersect(vertical.first, horizontal.first), intersect(vertical.last, horizontal.first),
                         intersect(vertical.last, horizontal.last), intersect(vertical.first, horizontal.last)]
        let corners = rectified.map { rough.apply(board($0.x, $0.y)) }
        guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        return corners
    }

    struct Direction {
        var combs: [Comb]
        var centres: [Double]
        /// First and last line as straight lines: `x = a + b·y` for vertical lines, `y = a + b·x` for horizontal ones.
        var first: (a: Double, b: Double)
        var last: (a: Double, b: Double)

    }

    /// The first and last line of one direction, fitted band by band.
    static func outerLines(in rect: GrayImage, vertical: Bool, lines: Int, seed: Comb? = nil) -> Direction? {
        let size = rect.width
        let bandSize = size / bands
        var firsts: [(Double, Double)] = [], lasts: [(Double, Double)] = []
        var spacings: [Double] = []
        var combs: [Comb] = [], centres: [Double] = []
        for b in 0..<bands {
            let range = (b * bandSize)..<min(size, (b + 1) * bandSize)
            if trace != nil {
                let pr = contrastProfile(rect, vertical: vertical, across: range).contrast
                let top = (pr.max() ?? 0) * 0.2
                let peaks = pr.indices.filter { $0 > 0 && $0 < pr.count - 1 && pr[$0] > top && pr[$0] >= pr[$0 - 1] && pr[$0] >= pr[$0 + 1] }
                trace?("  peaks: " + peaks.map { "\($0):\(Int(pr[$0] * 10))" }.joined(separator: " "))
            }
            let found = bestComb(rect, vertical: vertical, across: range, lines: lines, seed: seed)
            trace?("\(vertical ? "V" : "H") band \(b): " + (found.map { String(format: "first %.1f last %.1f spacing %.2f d %.4f", $0.first, $0.last, $0.spacing, $0.perspective) } ?? "no comb"))
            guard let comb = found else { return nil }
            let centre = Double(range.lowerBound + range.upperBound - 1) / 2
            firsts.append((comb.first, centre))
            lasts.append((comb.last, centre))
            spacings.append(comb.spacing)
            combs.append(comb); centres.append(centre)
        }
        guard let smin = spacings.min(), let smax = spacings.max(), smax - smin <= 0.15 * smin else {
            trace?("\(vertical ? "V" : "H"): band spacings disagree \(spacings)")
            return nil
        }
        return Direction(combs: combs, centres: centres, first: fitLine(firsts), last: fitLine(lasts))
    }


    /// Slopes tried for the lines of a band, in pixels of drift per pixel across the band.
    static let shears: [Double] = stride(from: -0.12, through: 0.12, by: 0.02).map { $0 }

    struct BandProfile {
        /// Thin-line response at each position.
        var contrast: [Double]
    }

    /// Thin-line profile of a band: how much darker position i is than *both* sides a third of a
    /// spacing away (the smaller of the two gains, floored at zero), averaged across the band along
    /// lines of slope `shear`. A step edge, such as the board's border, gives nothing.
    static func contrastProfile(_ rect: GrayImage, vertical: Bool, across band: Range<Int>, shear: Double = 0) -> BandProfile {
        let size = rect.width
        let w = Double(cell) / 3
        let centre = Double(band.lowerBound + band.upperBound - 1) / 2
        var out = [Double](repeating: 0, count: size)
        func value(_ along: Double, _ across: Double) -> Double {
            vertical ? rect.sample(x: along, y: across) : rect.sample(x: across, y: along)
        }
        let rows = Array(stride(from: band.lowerBound, to: band.upperBound, by: 2))
        for i in 0..<size {
            var sum = 0.0
            for j in rows {
                let y = Double(j)
                let x = Double(i) + shear * (y - centre)
                let c = value(x, y)
                sum += max(0, min(value(x - w, y) - c, value(x + w, y) - c))
            }
            out[i] = sum / Double(rows.count)
        }
        // Lines thinner than a pixel land a pixel or two off where they should: widen the peaks
        // so that the comb is scored on a smooth landscape (two box blurs of width 5).
        return BandProfile(contrast: smoothed(smoothed(out)))
    }

    static func smoothed(_ v: [Double]) -> [Double] {
        (0..<v.count).map { i in
            let lo = max(0, i - 2), hi = min(v.count - 1, i + 2)
            return v[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
    }

    /// How much evidence of *perpendicular* lines each position of the band carries, smoothed
    /// over a spacing. Rows of the grid are crossed by the vertical lines everywhere; the margin,
    /// the board's rim or its side face are not. Used to gate the line profile so that a comb
    /// cannot put a tooth where nothing crosses.
    static func perpendicularSupport(_ rect: GrayImage, vertical: Bool, across band: Range<Int>) -> [Double] {
        let size = rect.width
        let w = Double(cell) / 3
        func value(_ along: Double, _ across: Double) -> Double {
            vertical ? rect.sample(x: along, y: across) : rect.sample(x: across, y: along)
        }
        let rows = Array(stride(from: band.lowerBound, to: band.upperBound, by: 2))
        var out = [Double](repeating: 0, count: size)
        for i in stride(from: 0, to: size, by: 2) {
            let x = Double(i)
            var sum = 0.0
            for j in rows {
                let y = Double(j)
                let c = value(x, y)
                sum += max(0, min(value(x, y - w) - c, value(x, y + w) - c))
            }
            out[i] = sum / Double(rows.count)
            if i + 1 < size { out[i + 1] = out[i] }
        }
        // Dilate over half a spacing each way: the outer lines inherit the support of the cells
        // inside them, while anything further out than half a spacing keeps its own (low) support.
        let half = cell / 2
        return (0..<size).map { i in
            let lo = max(0, i - half), hi = min(size - 1, i + half)
            return out[lo...hi].max() ?? 0
        }
    }

    /// The comb of one band: a full fit on the unsheared profile, then refined on every shear
    /// so that slanted lines are followed; the sharpest wins. Profiles are gated by the
    /// perpendicular support.
    static func bestComb(_ rect: GrayImage, vertical: Bool, across band: Range<Int>, lines: Int, seed given: Comb? = nil) -> Comb? {
        let support = perpendicularSupport(rect, vertical: vertical, across: band)
        let sorted = support.sorted()
        let typical = sorted[sorted.count / 2]
        // Steep gate: below 35 % of the typical support nothing passes, above 65 % everything does.
        // The board's side face or a curtain behind it keep a third of the support, the grid all of it.
        let gate = support.map { value -> Double in
            guard typical > 0 else { return 1 }
            let t = min(max((value / typical - 0.35) / 0.3, 0), 1)
            return t * t * (3 - 2 * t)
        }
        trace?(String(format: "    support typical %.2f, every 40px: ", typical) + stride(from: 0, to: support.count, by: 40).map { String(format: "%.1f", support[$0]) }.joined(separator: " "))
        // A tooth where nothing crosses is not just worthless, it costs: this is what keeps the
        // comb from sliding one line into the margin or the side face when the far lines are faint.
        func gated(_ shear: Double) -> BandProfile {
            var p = contrastProfile(rect, vertical: vertical, across: band, shear: shear)
            p.contrast = zip(p.contrast, gate).map { $0 * $1 - unsupportedToothPenalty * (1 - $1) }
            return p
        }
        var seed = given
        if seed == nil {
            for shear in [0.0, 0.08, -0.08] {
                if let (comb, _) = fitComb(gated(shear), teeth: lines) {
                    seed = comb; break
                }
            }
        }
        guard let seed else { return nil }
        var best: Comb?
        var bestScore = -Double.infinity
        // Once seeded the rectification is already close: only small slants remain.
        let candidates = given == nil ? shears : shears.filter { abs($0) <= 0.045 }
        for shear in candidates {
            let profile = gated(shear)
            guard let (comb, score) = fitComb(profile, teeth: lines, near: seed) else { continue }
            if score > bestScore { bestScore = score; best = comb }
        }
        return best
    }

    /// `teeth` equally spaced board lines seen through a homography: a 1-D projective scale,
    /// parametrised by where the first and last teeth fall so that a one-pixel step in the search
    /// moves every tooth by at most one pixel.
    struct Comb {
        var first: Double
        var last: Double
        var teeth: Int
        /// Residual perspective: gaps shrink (d > 0) or grow (d < 0) along the profile.
        var perspective: Double

        var spacing: Double { (last - first) / Double(teeth - 1) }

        func position(_ k: Int) -> Double {
            let n = Double(teeth - 1), x = Double(k)
            return first + (last - first) * (x * (1 + perspective * n)) / (n * (1 + perspective * x))
        }
    }

    /// Best comb of `teeth` positions over the profile. With `near`, only a local search around
    /// that comb is done.
    static func fitComb(_ band: BandProfile, teeth: Int, near seed: Comb? = nil) -> (Comb, Double)? {
        let profile = band.contrast
        let count = Double(profile.count)
        func value(_ x: Double) -> Double {
            guard x >= 0, x <= count - 1 else { return -50 }      // teeth outside the image are penalised
            let i = Int(x), f = x - Double(i)
            return i + 1 < profile.count ? profile[i] * (1 - f) + profile[i + 1] * f : profile[i]
        }
        func score(_ c: Comb) -> Double {
            var s = 0.0
            for k in 0..<teeth { s += value(c.position(k)) }
            return s / Double(teeth)
        }
        var best = seed ?? Comb(first: 0, last: count - 1, teeth: teeth, perspective: 0)
        var bestScore = seed.map(score) ?? -Double.infinity
        if seed == nil {
            // The grid is expected to fill most of the rectified image: the first line lies in the
            // first third, the last one in the last third.
            let n = Double(teeth - 1)
            let minSpan = 0.75 * Double(cell) * n, maxSpan = 1.3 * Double(cell) * n
            for perspective in stride(from: -0.02, through: 0.02, by: 0.002) {
                var first = 0.0
                while first < count / 3 {
                    var last = max(first + minSpan, 2 * count / 3)
                    while last <= min(first + maxSpan, count - 1) {
                        let c = Comb(first: first, last: last, teeth: teeth, perspective: perspective)
                        let s = score(c)
                        if s > bestScore { bestScore = s; best = c }
                        last += 2
                    }
                    first += 2
                }
            }
        }
        let steps: [(Double, Double)] = [(2, 0.001), (1, 0.0005), (0.5, 0.0002), (0.1, 0.00005)]
        for (dPosition, dPerspective) in steps {
            var improved = true
            while improved {
                improved = false
                for (f, l, d) in [(dPosition, 0.0, 0.0), (-dPosition, 0.0, 0.0), (0.0, dPosition, 0.0), (0.0, -dPosition, 0.0), (0.0, 0.0, dPerspective), (0.0, 0.0, -dPerspective)] {
                    let candidate = Comb(first: best.first + f, last: best.last + l, teeth: teeth, perspective: best.perspective + d)
                    let sc = score(candidate)
                    if sc > bestScore + 1e-9 { bestScore = sc; best = candidate; improved = true }
                }
            }
        }
        let mean = profile.reduce(0, +) / count
        trace?(String(format: "  comb score %.2f (profile mean %.2f, max %.2f)%@", bestScore, mean, profile.max() ?? 0, bestScore < minimumContrast ? " rejected" : ""))
        return bestScore >= minimumContrast ? (best, bestScore) : nil
    }

    /// Least-squares line `p = a + b·q` through (p, q) samples.
    static func fitLine(_ points: [(Double, Double)]) -> (a: Double, b: Double) {
        let n = Double(points.count)
        let mp = points.map(\.0).reduce(0, +) / n, mq = points.map(\.1).reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (p, q) in points { num += (q - mq) * (p - mp); den += (q - mq) * (q - mq) }
        let b = den > 0 ? num / den : 0
        return (mp - b * mq, b)
    }
}
