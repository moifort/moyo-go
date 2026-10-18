import Foundation

public struct ReaderSettings: Sendable, Equatable, Codable {
    /// Radius of the measuring disk at an intersection, in line spacings. Small enough that a
    /// stone's cast shadow on the next intersection does not fill the disk.
    public var stoneRadius = 0.30
    /// Radius of the wood disks at the four adjacent cell centres, in line spacings.
    public var woodRadius = 0.15
    /// Stone thickness as a fraction of the line spacing, used with the local viewing angle to
    /// follow a stone's body away from the camera. Seen from the stand, a stone's widest part
    /// sits a third of a cell beyond its intersection, and a disk left on the intersection only
    /// catches the rim: a few pixels of drift then lose every white stone on the far rows.
    /// 0.4 is a 9 mm stone on a 22 mm grid.
    public var stoneHeight = 0.4
    /// The lift never exceeds this, in spacings, so that the disk stays short of the next
    /// intersection's stone on photos where the far rows are compressed to a few pixels.
    public var maxLift = 0.45
    /// How far past the side lines, in spacings, the disk may follow a stone's body: the wood
    /// margin of a board is about half a spacing.
    public var edgeMargin = 0.3
    /// Black when stone / wood is below this.
    public var blackBelow = 0.55
    /// White when stone / wood is above this, or when the headroom fraction is above `whiteHeadroom`.
    /// Low on purpose: an empty intersection reads below the wood because of the line crossing,
    /// while light wood leaves a white stone little room above it.
    public var whiteAbove = 1.15
    /// White when (stone - wood) / (255 - wood) is above this: bright wood leaves little ratio.
    public var whiteHeadroom = 0.5
    /// An existing black stone stays while its contrast is below this.
    public var keepBlackBelow = 0.70
    /// An existing white stone stays while its contrast or headroom is above these.
    public var keepWhiteAbove = 1.08
    public var keepWhiteHeadroom = 0.35
    /// Standard deviation inside the stone disk above which the intersection is unreadable.
    /// Deliberately high: synthetic line crossings already reach 60. To be tuned on real photos.
    public var maxDeviation = 80.0
    /// A stone that was not there before is only taken when the disk is this uniform: inside
    /// a stone's body the deviation stays under 20 on real photos, while a disk straddling the
    /// rim of the neighbour's stone, which leans into this cell, reaches 45 and more. Such an
    /// intersection is left unreadable, and keeps what it had.
    public var maxNewStoneDeviation = 40.0

    public init() {}
}

/// What one image says about the board.
public struct Readings: Sendable, Equatable {
    public var position: Position
    /// Intersections whose content could not be decided on this image.
    public var unreadable: Set<Intersection>

    public init(position: Position, unreadable: Set<Intersection> = []) {
        self.position = position
        self.unreadable = unreadable
    }
}

/// Reads each intersection against its own neighbourhood, so lighting gradients and shadows cancel out.
public struct IntersectionReader: Sendable {
    public let geometry: BoardGeometry
    public var settings: ReaderSettings

    /// Sample offsets inside a unit disk, in board units before scaling by the radius.
    private static let diskOffsets: [(Double, Double)] = {
        var out: [(Double, Double)] = []
        let n = 4
        for j in -n...n {
            for i in -n...n {
                let x = Double(i) / Double(n), y = Double(j) / Double(n)
                if x * x + y * y <= 1 { out.append((x, y)) }
            }
        }
        return out
    }()

    public init(geometry: BoardGeometry, settings: ReaderSettings = ReaderSettings()) {
        self.geometry = geometry
        self.settings = settings
    }

    public struct Measure: Sendable, Equatable {
        public let stone: Double
        public let wood: Double
        public let deviation: Double
        /// stone / wood: below 1 for black, above 1 for white.
        public var contrast: Double { stone / max(wood, 1) }
        /// Fraction of the remaining brightness above the wood that the stone fills.
        public var headroom: Double { (stone - wood) / max(255 - wood, 1) }
    }

    /// Where, in spacings, the body of a stone at `i` appears to sit on the board: the point of
    /// the board plane under the image of the stone's mid-height. Seen through the camera the
    /// shift points away from it, with a sideways part near the frame's edges; without a usable
    /// camera it follows `awayFromCamera` by h / 2 · cos θ / sin θ. Capped at `maxLift` and
    /// kept on the board, so the far line reads where it is.
    public func stoneShift(at i: Intersection, in image: GrayImage) -> (Double, Double) {
        guard settings.stoneHeight > 0 else { return (0, 0) }
        let p = Point(x: Double(i.col), y: Double(i.row))
        var shift: (Double, Double)
        if let camera = geometry.camera(imageWidth: image.width, imageHeight: image.height) {
            let q = geometry.toBoard.apply(camera.project(p, height: settings.stoneHeight / 2))
            shift = (q.x - p.x, q.y - p.y)
        } else {
            let away = geometry.awayFromCamera
            shift = (away.0 * axisLift(at: i), away.1 * axisLift(at: i))
        }
        let length = (shift.0 * shift.0 + shift.1 * shift.1).squareRoot()
        if length > settings.maxLift { shift = (shift.0 * settings.maxLift / length, shift.1 * settings.maxLift / length) }
        // Not past the far line, where the background begins; sideways the wood goes on for
        // a while past the last line, and a stone on it leans out over that margin.
        let n = Double(geometry.lines - 1), margin = settings.edgeMargin
        let away = geometry.awayFromCamera
        let coordinate = away.0 != 0 ? p.x : p.y
        let farLine = away.0 + away.1 > 0 ? n : 0
        if abs(coordinate - farLine) < 1e-9 { return (0, 0) }
        let (mx, my) = away.0 == 0 ? (margin, 0.0) : (0.0, margin)
        shift.0 = min(max(shift.0, -p.x - mx), n - p.x + mx)
        shift.1 = min(max(shift.1, -p.y - my), n - p.y + my)
        return shift
    }

    /// A stone of height h seen at elevation θ has its top projected h / tan θ further away;
    /// the visible body is centred about half of that.
    func axisLift(at i: Intersection) -> Double {
        let away = geometry.awayFromCamera
        let here = geometry.imagePoint(boardX: Double(i.col), boardY: Double(i.row))
        let along = geometry.imagePoint(boardX: Double(i.col) + away.0, boardY: Double(i.row) + away.1)
        let across = geometry.imagePoint(boardX: Double(i.col) + away.1, boardY: Double(i.row) + away.0)
        let depth = BoardGeometry.distance(here, along)
        let width = BoardGeometry.distance(here, across)
        guard width > 0 else { return 0 }
        let sine = min(depth / width, 1)
        let cosine = (1 - sine * sine).squareRoot()
        guard sine > 0.05 else { return 0 }
        return settings.stoneHeight / 2 * cosine / sine
    }

    /// Measures `i`, taking the wood from cells no stone can hide when `occupied` is given.
    ///
    /// Seen from low, a stone covers the cells behind it in the image, and its own top covers
    /// the cells just beyond it: in a tight shape all four adjacent cells can show stones, and a
    /// white stone next to white stones then reads as empty. When a neighbour in `occupied`
    /// touches an adjacent cell, the wood comes from the cells of the surrounding 4×4 block
    /// that no stone of `occupied` touches, minus the two just beyond `i`.
    public func measure(_ image: GrayImage, at i: Intersection, occupied: Set<Intersection>) -> Measure {
        let base = measure(image, at: i)
        let near = [-0.5, 0.5]
        guard near.contains(where: { dy in near.contains { dx in touched(Double(i.col) + dx, Double(i.row) + dy, by: occupied, except: i) } }),
              let wood = blockWood(image, at: i, occupied: occupied) else { return base }
        return Measure(stone: base.stone, wood: wood, deviation: base.deviation)
    }

    /// A stone alone, set a little off its intersection, covers one of the four adjacent cells:
    /// that cell then reads as bright, or as dark, as the stone and lifts the wood reference.
    /// Nil unless both the 4×4 block and the adjacent cells without the one most like the stone
    /// say there is a stone.
    public func loneStone(_ image: GrayImage, at i: Intersection, previous: Stone?) -> Stone? {
        let base = measure(image, at: i)
        guard base.deviation <= settings.maxNewStoneDeviation,
              let block = blockWood(image, at: i, occupied: []) else { return nil }
        let byBlock = Self.classify(Measure(stone: base.stone, wood: block, deviation: base.deviation), previous: previous, settings: settings)
        guard byBlock != .empty else { return nil }
        let n = Double(geometry.lines - 1)
        let shift = stoneShift(at: i, in: image)
        let (cx, cy) = (Double(i.col) + shift.0, Double(i.row) + shift.1)
        var adjacent: [Double] = []
        for dy in [-0.5, 0.5] {
            for dx in [-0.5, 0.5] {
                let x = cx + dx, y = cy + dy
                guard x > 0, y > 0, x < n, y < n else { continue }
                let s = disk(image, cx: x, cy: y, radius: settings.woodRadius)
                adjacent.append(s.reduce(0, +) / Double(s.count))
            }
        }
        guard adjacent.count >= 3 else { return nil }
        // Without the cell the stone covers, the stone must still beat the cell most like it:
        // a patch of sunlight next to a shaded cell beats only the shaded one.
        adjacent.sort()
        let wood = byBlock == .white ? adjacent[adjacent.count - 2] : adjacent[1]
        let byAdjacent = Self.classify(Measure(stone: base.stone, wood: wood, deviation: base.deviation), previous: previous, settings: settings)
        return byAdjacent == byBlock ? byBlock : nil
    }

    /// True when a stone of `occupied` other than `except` sits at a corner of the cell centred at (x, y).
    private func touched(_ x: Double, _ y: Double, by occupied: Set<Intersection>, except: Intersection) -> Bool {
        for cx in [x - 0.5, x + 0.5] {
            for cy in [y - 0.5, y + 0.5] {
                let corner = Intersection(col: Int(cx.rounded()), row: Int(cy.rounded()))
                if corner != except, occupied.contains(corner) { return true }
            }
        }
        return false
    }

    /// Median wood of the 4×4 block of cells around the lifted centre of `i`, leaving out the
    /// cells a stone of `occupied` touches and the two just beyond `i`. In a corner where
    /// stones touch every cell, the median of the whole block, which a few stone bodies do not
    /// move. Nil with fewer than three cells on the board.
    private func blockWood(_ image: GrayImage, at i: Intersection, occupied: Set<Intersection>) -> Double? {
        let shift = stoneShift(at: i, in: image)
        let away = shift == (0, 0) ? geometry.awayFromCamera : shift
        let n = Double(geometry.lines - 1)
        let (cx, cy) = (Double(i.col) + shift.0, Double(i.row) + shift.1)
        var free: [Double] = [], all: [Double] = []
        for dy in [-1.5, -0.5, 0.5, 1.5] {
            for dx in [-1.5, -0.5, 0.5, 1.5] {
                let x = cx + dx, y = cy + dy
                guard x > 0, y > 0, x < n, y < n else { continue }
                let beyond = abs(dx) == 0.5 && abs(dy) == 0.5 && dx * away.0 + dy * away.1 > 0
                if beyond { continue }
                let s = disk(image, cx: x, cy: y, radius: settings.woodRadius)
                let wood = s.reduce(0, +) / Double(s.count)
                all.append(wood)
                if !touched(x, y, by: occupied, except: i) { free.append(wood) }
            }
        }
        let woods = free.count >= 3 ? free : all
        guard woods.count >= 3 else { return nil }
        return woods.sorted()[woods.count / 2]
    }

    /// True when the disk of `i` lands inside the body of a stone of `occupied` leaning over
    /// it: on the far line the disk cannot move off the board, and the stone just in front
    /// covers it. Only a stone whose body leans towards `i` counts, so the stone in front is
    /// never covered by the one it hides.
    private func covered(_ i: Intersection, by occupied: Set<Intersection>, in image: GrayImage) -> Bool {
        let shift = stoneShift(at: i, in: image)
        let (cx, cy) = (Double(i.col) + shift.0, Double(i.row) + shift.1)
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let other = Intersection(col: i.col + dx, row: i.row + dy)
                guard occupied.contains(other) else { continue }
                let s = stoneShift(at: other, in: image)
                guard s.0 * Double(-dx) + s.1 * Double(-dy) > 0 else { continue }
                let ox = Double(other.col) + s.0 - cx, oy = Double(other.row) + s.1 - cy
                if (ox * ox + oy * oy).squareRoot() < settings.stoneRadius + Self.bodyRadius { return true }
            }
        }
        return false
    }

    /// Apparent radius of a stone's body, in spacings.
    static let bodyRadius = 0.47

    public func measure(_ image: GrayImage, at i: Intersection) -> Measure {
        measure(image, at: i, shift: stoneShift(at: i, in: image))
    }

    /// Measures `i` with the stone disk, and the wood cells around it, moved by `shift`
    /// spacings: the wood follows the disk so that a patch of sunlight a cell away does not
    /// pass for a stone.
    public func measure(_ image: GrayImage, at i: Intersection, shift: (Double, Double)) -> Measure {
        let cx = Double(i.col) + shift.0
        let cy = Double(i.row) + shift.1
        let samples = disk(image, cx: cx, cy: cy, radius: settings.stoneRadius)
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)

        var woods: [Double] = []
        let n = geometry.lines - 1
        for dy in [-0.5, 0.5] {
            for dx in [-0.5, 0.5] {
                let x = cx + dx, y = cy + dy
                guard x > 0, y > 0, x < Double(n), y < Double(n) else { continue }
                let s = disk(image, cx: x, cy: y, radius: settings.woodRadius)
                woods.append(s.reduce(0, +) / Double(s.count))
            }
        }
        let sorted = woods.sorted()
        let wood = sorted.isEmpty ? mean : sorted[sorted.count / 2]
        return Measure(stone: mean, wood: wood, deviation: variance.squareRoot())
    }

    private func disk(_ image: GrayImage, cx: Double, cy: Double, radius: Double) -> [Double] {
        Self.diskOffsets.map { ox, oy in
            let p = geometry.imagePoint(boardX: cx + ox * radius, boardY: cy + oy * radius)
            return image.sample(x: p.x, y: p.y)
        }
    }

    /// Classifies `m`, measured with the disk lifted, and confirms a black stone on the
    /// intersection itself: a black stone's rim sits there, while the lifted disk of the empty
    /// intersection in front of one lands in its cast shadow.
    /// Nil when a new stone shows but the disk is not uniform enough to take it.
    private func classify(_ m: Measure, at i: Intersection, previous: Stone?, in image: GrayImage) -> Stone? {
        var stone = Self.classify(m, previous: previous, settings: settings)
        if stone == .black, stoneShift(at: i, in: image) != (0, 0) {
            let flat = measure(image, at: i, shift: (0, 0))
            let onIntersection = Measure(stone: flat.stone, wood: m.wood, deviation: flat.deviation)
            stone = Self.classify(onIntersection, previous: previous, settings: settings) == .black ? .black : .empty
        }
        if stone != .empty, stone != previous, m.deviation > settings.maxNewStoneDeviation { return nil }
        return stone
    }

    public static func classify(_ m: Measure, previous: Stone?, settings: ReaderSettings) -> Stone {
        switch previous {
        case .black? where m.contrast < settings.keepBlackBelow:
            return .black
        case .white? where m.contrast > settings.keepWhiteAbove || m.headroom > settings.keepWhiteHeadroom:
            return .white
        default:
            if m.contrast < settings.blackBelow { return .black }
            if m.contrast > settings.whiteAbove || m.headroom > settings.whiteHeadroom { return .white }
            return .empty
        }
    }

    /// Reads the whole board. `previous` enables the hysteresis on already-known stones.
    ///
    /// Two passes: the first finds the stones, the second measures again the intersections next
    /// to one, with the wood taken from cells those stones cannot hide.
    public func read(_ image: GrayImage, previous: Position?) -> Readings {
        var position = Position(size: geometry.lines)
        var unreadable: Set<Intersection> = []
        var measures: [Intersection: Measure] = [:]
        for i in position.all {
            let m = measure(image, at: i)
            measures[i] = m
            if m.deviation > settings.maxDeviation {
                unreadable.insert(i)
                position[i] = previous?[i] ?? .empty
            } else {
                if let stone = classify(m, at: i, previous: previous?[i], in: image) {
                    position[i] = stone
                } else {
                    unreadable.insert(i)
                    position[i] = previous?[i] ?? .empty
                }
            }
        }

        var occupied = Set(position.stones.keys)
        if let previous { occupied.formUnion(previous.stones.keys) }
        let first = position
        var lone: [Intersection: Stone] = [:]
        for i in first.all where !unreadable.contains(i) {
            let hasNeighbour = (-1...1).contains { dy in
                (-1...1).contains { dx in
                    (dx != 0 || dy != 0) && occupied.contains(Intersection(col: i.col + dx, row: i.row + dy))
                }
            }
            if hasNeighbour {
                if covered(i, by: occupied.subtracting([i]), in: image) {
                    unreadable.insert(i)
                    position[i] = previous?[i] ?? .empty
                    continue
                }
                let m = measure(image, at: i, occupied: occupied)
                if m != measures[i] {
                    if let stone = classify(m, at: i, previous: previous?[i], in: image) {
                        position[i] = stone
                    } else {
                        unreadable.insert(i)
                        position[i] = previous?[i] ?? .empty
                    }
                }
            } else if first[i] == .empty, let stone = loneStone(image, at: i, previous: previous?[i]) {
                lone[i] = stone
            }
        }
        // A lone stone's top covers the intersection just beyond it, which then passes for a lone
        // stone of the same colour: keep only the nearer of the two.
        let away = (col: Int(geometry.awayFromCamera.0), row: Int(geometry.awayFromCamera.1))
        for (i, stone) in lone {
            let nearer = Intersection(col: i.col - away.col, row: i.row - away.row)
            if lone[nearer] != stone { position[i] = stone }
        }
        return Readings(position: position, unreadable: unreadable)
    }
}
