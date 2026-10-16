import Foundation

/// Lets a change through only after it has been read identically on `required` consecutive images.
public struct StabilityFilter: Sendable {
    public let required: Int
    private var stable: Position
    private var last: [Stone]
    private var streak: [Int]

    public init(start: Position, required: Int = 3) {
        precondition(required >= 1)
        self.required = required
        stable = start
        last = start.all.map { start[$0] }
        streak = [Int](repeating: required, count: start.size * start.size)
    }

    /// Adopts a new accepted position and forgets pending changes.
    public mutating func reset(to position: Position) {
        stable = position
        last = position.all.map { position[$0] }
        streak = [Int](repeating: required, count: position.size * position.size)
    }

    /// Feeds one image's readings and returns the candidate position.
    public mutating func push(_ readings: Readings) -> Position {
        let size = stable.size
        for i in stable.all {
            let k = i.row * size + i.col
            if readings.unreadable.contains(i) {
                streak[k] = 0
                continue
            }
            let value = readings.position[i]
            if value == last[k] {
                streak[k] += 1
            } else {
                last[k] = value
                streak[k] = 1
            }
            if streak[k] >= required { stable[i] = value }
        }
        return stable
    }
}
