import Foundation

/// A move as written in the record, with what the referee had to force alongside it.
public struct RecordedMove: Sendable, Equatable {
    public let move: Move
    /// Stones removed from the board without a capture, accepted by the user ("C'est bon").
    public let erased: [Intersection]
    /// True when the order was imposed by the referee rather than observed.
    public let uncertain: Bool

    public init(move: Move, erased: [Intersection] = [], uncertain: Bool = false) {
        self.move = move
        self.erased = erased
        self.uncertain = uncertain
    }
}

/// The game as recorded: starting position, moves, and the positions reached.
public struct GameRecord: Sendable, Equatable {
    public let size: Int
    public let date: Date
    public let setupBlack: [Intersection]
    public let setupWhite: [Intersection]
    public let handicap: Int
    public private(set) var moves: [RecordedMove] = []
    /// Positions reached, index 0 being the starting position.
    public private(set) var positions: [Position]

    public static let maxTakeBack = 3

    public init(start: Position, date: Date = Date()) {
        size = start.size
        self.date = date
        let stones = start.stones
        setupBlack = stones.filter { $0.value == .black }.keys.sorted()
        setupWhite = stones.filter { $0.value == .white }.keys.sorted()
        handicap = (setupWhite.isEmpty && setupBlack.count >= 2) ? setupBlack.count : 0
        positions = [start]
    }

    public var position: Position { positions.last! }

    public var toPlay: Stone {
        if let last = moves.last { return last.move.color.opponent }
        return handicap > 0 ? .white : .black
    }

    /// Appends moves already validated by the rules.
    public mutating func apply(_ sequence: [Move]) {
        for move in sequence {
            guard let next = Rules.play(move, on: position) else { continue }
            moves.append(RecordedMove(move: move))
            positions.append(next)
        }
    }

    /// Returns to an earlier position reached at most `maxTakeBack` moves ago. False if unknown.
    public mutating func takeBack(to target: Position) -> Bool {
        let lowest = max(0, positions.count - 1 - Self.maxTakeBack)
        guard let index = positions.indices.reversed().first(where: { $0 >= lowest && $0 < positions.count - 1 && positions[$0] == target }) else {
            return false
        }
        positions.removeSubrange((index + 1)...)
        moves.removeSubrange(index...)
        return true
    }

    /// Makes `seen` the accepted position: added stones become moves in alternation order
    /// (same colour: by coordinates), removed stones are written as erasures on the next move.
    public mutating func force(to seen: Position) {
        let diff = position.diff(to: seen)
        var erased = diff.filter { $0.value == .empty }.keys.sorted()
        var added = diff.filter { $0.value != .empty }.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
        var color = toPlay
        var next = position
        for e in erased { next[e] = .empty }
        while !added.isEmpty {
            let index = added.firstIndex { $0.1 == color } ?? 0
            let (point, stone) = added.remove(at: index)
            next[point] = stone
            moves.append(RecordedMove(move: Move(color: stone, point: point), erased: erased, uncertain: true))
            positions.append(next)
            erased = []
            color = stone.opponent
        }
        if !erased.isEmpty {
            // Removals alone: attach them to a pass so they appear in the file.
            moves.append(RecordedMove(move: Move(color: color, point: nil), erased: erased, uncertain: true))
            positions.append(next)
        }
    }
}
