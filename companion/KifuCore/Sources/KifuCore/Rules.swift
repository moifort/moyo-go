import Foundation

/// A move: a stone placed at `point`, or a pass when `point` is nil.
public struct Move: Sendable, Equatable, Hashable {
    public let color: Stone
    public let point: Intersection?
    public init(color: Stone, point: Intersection?) {
        self.color = color
        self.point = point
    }
    public var isPass: Bool { point == nil }
}

/// Go rules without ko: placement, captures, suicide.
public enum Rules {
    /// Applies `move` to `position`. Nil when the point is occupied or the move is suicide.
    public static func play(_ move: Move, on position: Position) -> Position? {
        guard let point = move.point else { return position }
        guard position.contains(point), position[point] == .empty, move.color != .empty else { return nil }
        var next = position
        next[point] = move.color
        for n in next.neighbours(of: point) where next[n] == move.color.opponent {
            let (group, liberties) = groupAndLiberties(at: n, in: next)
            if liberties == 0 { for g in group { next[g] = .empty } }
        }
        let (_, ownLiberties) = groupAndLiberties(at: point, in: next)
        guard ownLiberties > 0 else { return nil }
        return next
    }

    /// Connected stones of the same colour as `start`, and the count of their liberties.
    public static func groupAndLiberties(at start: Intersection, in position: Position) -> (group: Set<Intersection>, liberties: Int) {
        let color = position[start]
        guard color != .empty else { return ([], 0) }
        var group: Set<Intersection> = [start]
        var liberties: Set<Intersection> = []
        var stack = [start]
        while let i = stack.popLast() {
            for n in position.neighbours(of: i) {
                switch position[n] {
                case .empty: liberties.insert(n)
                case color where !group.contains(n):
                    group.insert(n); stack.append(n)
                default: break
                }
            }
        }
        return (group, liberties.count)
    }

    /// The most stones explained by a single change: hands over the board can hide a few
    /// moves played in quick succession.
    public static let maxStonesPerChange = 4

    /// Moves explaining a change, and whether their order had to be guessed.
    public struct Explanation: Sendable, Equatable {
        public let moves: [Move]
        /// More than one legal order leads to the same position: the one kept is a guess.
        public let guessedOrder: Bool
    }

    /// The sequence of moves that leads exactly from `from` to `to`, or nil.
    public static func explain(from: Position, to: Position, toPlay: Stone) -> [Move]? {
        explanation(from: from, to: to, toPlay: toPlay)?.moves
    }

    /// At most `maxStonesPerChange` stones placed, alternating from `toPlay`. A single implicit
    /// pass is tolerated when the only new stone belongs to the other side. Captures are applied
    /// by the rules and must match the stones that disappeared. Among the orders that fit, the
    /// first by coordinates is kept.
    public static func explanation(from: Position, to: Position, toPlay: Stone) -> Explanation? {
        explanation(from: from, to: to, toPlay: toPlay, matching: { $0 == to })
    }

    /// Same as `explanation`, but the final position is accepted by `matching` instead of strict equality.
    static func explanation(from: Position, to: Position, toPlay: Stone, matching: (Position) -> Bool) -> Explanation? {
        guard from.size == to.size, toPlay != .empty else { return nil }
        var added: [(Intersection, Stone)] = []
        for (i, stone) in from.diff(to: to).sorted(by: { $0.key < $1.key }) {
            if stone != .empty {
                guard from[i] == .empty else { return nil }    // colour change
                added.append((i, stone))
            }
        }
        if added.isEmpty { return from == to ? Explanation(moves: [], guessedOrder: false) : nil }
        guard added.count <= maxStonesPerChange else { return nil }

        if added.count == 1 {
            let (i, stone) = added[0]
            var sequence: [Move] = []
            if stone != toPlay { sequence.append(Move(color: toPlay, point: nil)) }
            sequence.append(Move(color: stone, point: i))
            guard let end = play(sequence, on: from), matching(end) else { return nil }
            return Explanation(moves: sequence, guessedOrder: false)
        }

        // Alternation from the side to play: as many stones as the other side, or one more.
        let mine = added.filter { $0.1 == toPlay }.map(\.0)
        let theirs = added.filter { $0.1 != toPlay }.map(\.0)
        guard mine.count == theirs.count || mine.count == theirs.count + 1 else { return nil }

        var found: [Move]?
        var fits = 0
        for a in permutations(mine) {
            for b in permutations(theirs) {
                var sequence: [Move] = []
                for k in 0..<mine.count {
                    sequence.append(Move(color: toPlay, point: a[k]))
                    if k < b.count { sequence.append(Move(color: toPlay.opponent, point: b[k])) }
                }
                guard let end = play(sequence, on: from), matching(end) else { continue }
                fits += 1
                if found == nil { found = sequence }
            }
        }
        return found.map { Explanation(moves: $0, guessedOrder: fits > 1) }
    }

    /// Plays `moves` in turn, nil as soon as one is illegal.
    static func play(_ moves: [Move], on position: Position) -> Position? {
        var position = position
        for move in moves {
            guard let next = play(move, on: position) else { return nil }
            position = next
        }
        return position
    }

    /// Every order of `items`, the given order first.
    static func permutations<T>(_ items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { i -> [[T]] in
            var rest = items; let head = rest.remove(at: i)
            return permutations(rest).map { [head] + $0 }
        }
    }

    /// True when `to` is `from` plus a legal sequence whose captured stones are still on the board.
    public static func isAwaitingCaptureRemoval(from: Position, to: Position, toPlay: Stone) -> Bool {
        // Every stone the rules would capture is still shown in `to` with its colour, nothing else differs.
        let explained = explanation(from: from, to: to, toPlay: toPlay, matching: { result in
            var captured = false
            for i in result.all where result[i] != to[i] {
                guard result[i] == .empty, from[i] != .empty, to[i] == from[i] else { return false }
                captured = true
            }
            return captured
        })
        return !(explained?.moves ?? []).isEmpty
    }
}
