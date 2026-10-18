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

    /// How far, in spacings, the top of a stone at `i` appears shifted away from the camera.
    /// A stone of height h seen at elevation θ has its top projected h / tan θ further away;
    /// the visible body is centred about half of that.
    public func stoneLift(at i: Intersection) -> Double {
        guard settings.stoneHeight > 0 else { return 0 }
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
        var lift = min(settings.stoneHeight / 2 * cosine / sine, settings.maxLift)
        // On the far line the lifted disk would read whatever lies beyond the board.
        let n = Double(geometry.lines - 1)
        let room = away.0 > 0 ? n - Double(i.col) : away.0 < 0 ? Double(i.col) : away.1 > 0 ? n - Double(i.row) : Double(i.row)
        lift = min(lift, max(room, 0))
        return lift
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
        guard let block = blockWood(image, at: i, occupied: []) else { return nil }
        let byBlock = Self.classify(Measure(stone: base.stone, wood: block, deviation: base.deviation), previous: previous, settings: settings)
        guard byBlock != .empty else { return nil }
        let n = Double(geometry.lines - 1)
        let (cx, cy) = liftedCentre(of: i)
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

    /// Where the stone disk of `i` is measured: its intersection, moved by the lift away from the camera.
    private func liftedCentre(of i: Intersection) -> (Double, Double) {
        let away = geometry.awayFromCamera
        let lift = stoneLift(at: i)
        return (Double(i.col) + away.0 * lift, Double(i.row) + away.1 * lift)
    }

    /// Median wood of the 4×4 block of cells around the lifted centre of `i`, leaving out the
    /// cells a stone of `occupied` touches and the two just beyond `i`. Nil with fewer than
    /// three cells left.
    private func blockWood(_ image: GrayImage, at i: Intersection, occupied: Set<Intersection>) -> Double? {
        let away = geometry.awayFromCamera
        let n = Double(geometry.lines - 1)
        let (cx, cy) = liftedCentre(of: i)
        var woods: [Double] = []
        for dy in [-1.5, -0.5, 0.5, 1.5] {
            for dx in [-1.5, -0.5, 0.5, 1.5] {
                let x = cx + dx, y = cy + dy
                guard x > 0, y > 0, x < n, y < n, !touched(x, y, by: occupied, except: i) else { continue }
                let beyond = abs(dx) == 0.5 && abs(dy) == 0.5 && dx * away.0 + dy * away.1 > 0
                if beyond { continue }
                let s = disk(image, cx: x, cy: y, radius: settings.woodRadius)
                woods.append(s.reduce(0, +) / Double(s.count))
            }
        }
        guard woods.count >= 3 else { return nil }
        return woods.sorted()[woods.count / 2]
    }

    public func measure(_ image: GrayImage, at i: Intersection) -> Measure {
        measure(image, at: i, lift: stoneLift(at: i))
    }

    /// Measures `i` with the stone disk, and the wood cells around it, moved `lift` spacings
    /// away from the camera: the wood follows the disk so that a patch of sunlight a cell away
    /// does not pass for a stone.
    public func measure(_ image: GrayImage, at i: Intersection, lift: Double) -> Measure {
        let away = geometry.awayFromCamera
        let cx = Double(i.col) + away.0 * lift
        let cy = Double(i.row) + away.1 * lift
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
    private func classify(_ m: Measure, at i: Intersection, previous: Stone?, in image: GrayImage) -> Stone {
        let stone = Self.classify(m, previous: previous, settings: settings)
        guard stone == .black, stoneLift(at: i) > 0 else { return stone }
        let flat = measure(image, at: i, lift: 0)
        let onIntersection = Measure(stone: flat.stone, wood: m.wood, deviation: flat.deviation)
        return Self.classify(onIntersection, previous: previous, settings: settings) == .black ? .black : .empty
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
                position[i] = classify(m, at: i, previous: previous?[i], in: image)
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
                let m = measure(image, at: i, occupied: occupied)
                if m != measures[i] { position[i] = classify(m, at: i, previous: previous?[i], in: image) }
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
