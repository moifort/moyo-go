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

    /// The sequence of moves that leads exactly from `from` to `to`, or nil.
    ///
    /// At most two stones placed, alternating from `toPlay`. A single implicit pass is
    /// tolerated right before a placement when the first stone belongs to the other side.
    /// Captures are applied by the rules and must match the stones that disappeared.
    public static func explain(from: Position, to: Position, toPlay: Stone) -> [Move]? {
        explain(from: from, to: to, toPlay: toPlay, matching: { $0 == to })
    }

    /// Same as `explain`, but the final position is accepted by `matching` instead of strict equality.
    static func explain(from: Position, to: Position, toPlay: Stone, matching: (Position) -> Bool) -> [Move]? {
        guard from.size == to.size, toPlay != .empty else { return nil }
        var added: [(Intersection, Stone)] = []
        for (i, stone) in from.diff(to: to).sorted(by: { $0.key < $1.key }) {
            if stone != .empty {
                guard from[i] == .empty else { return nil }    // colour change
                added.append((i, stone))
            }
        }
        if added.isEmpty { return from == to ? [] : nil }
        guard added.count <= 2 else { return nil }

        var sequence: [Move] = []
        if added.count == 1 {
            let (i, stone) = added[0]
            if stone != toPlay { sequence.append(Move(color: toPlay, point: nil)) }
            sequence.append(Move(color: stone, point: i))
        } else {
            guard added[0].1 != added[1].1 else { return nil }
            let first = added.first { $0.1 == toPlay }!
            let second = added.first { $0.1 != toPlay }!
            sequence = [Move(color: first.1, point: first.0), Move(color: second.1, point: second.0)]
        }

        var position = from
        for move in sequence {
            guard let next = play(move, on: position) else { return nil }
            position = next
        }
        return matching(position) ? sequence : nil
    }

    /// True when `to` is `from` plus a legal sequence whose captured stones are still on the board.
    public static func isAwaitingCaptureRemoval(from: Position, to: Position, toPlay: Stone) -> Bool {
        // Every stone the rules would capture is still shown in `to` with its colour, nothing else differs.
        let moves = explain(from: from, to: to, toPlay: toPlay, matching: { result in
            var captured = false
            for i in result.all where result[i] != to[i] {
                guard result[i] == .empty, from[i] != .empty, to[i] == from[i] else { return false }
                captured = true
            }
            return captured
        })
        return !(moves ?? []).isEmpty
    }
}
