import Foundation

public struct ReaderSettings: Sendable, Equatable, Codable {
    /// Radius of the measuring disk at an intersection, in line spacings. Small enough that a
    /// stone's cast shadow on the next intersection does not fill the disk.
    public var stoneRadius = 0.30
    /// Radius of the wood disks at the four adjacent cell centres, in line spacings.
    public var woodRadius = 0.15
    /// Stone thickness as a fraction of the line spacing, used with the local viewing angle to
    /// follow a stone's top away from the camera. Zero by default: on the reference photo the
    /// cast shadows fall towards the camera and the far rows are so compressed that lifting the
    /// disk reads the background beyond the board. Kept for tuning on more photos.
    public var stoneHeight = 0.0
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
        return settings.stoneHeight / 2 * cosine / sine
    }

    public func measure(_ image: GrayImage, at i: Intersection) -> Measure {
        let away = geometry.awayFromCamera
        let lift = stoneLift(at: i)
        let cx = Double(i.col) + away.0 * lift
        let cy = Double(i.row) + away.1 * lift
        let samples = disk(image, cx: cx, cy: cy, radius: settings.stoneRadius)
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)

        var woods: [Double] = []
        let n = geometry.lines - 1
        for dy in [-0.5, 0.5] {
            for dx in [-0.5, 0.5] {
                let x = Double(i.col) + dx, y = Double(i.row) + dy
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
    public func read(_ image: GrayImage, previous: Position?) -> Readings {
        var position = Position(size: geometry.lines)
        var unreadable: Set<Intersection> = []
        for i in position.all {
            let m = measure(image, at: i)
            if m.deviation > settings.maxDeviation {
                unreadable.insert(i)
                position[i] = previous?[i] ?? .empty
            } else {
                position[i] = Self.classify(m, previous: previous?[i], settings: settings)
            }
        }
        return Readings(position: position, unreadable: unreadable)
    }
}
