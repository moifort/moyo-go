import Foundation

public enum Stone: Sendable, Equatable, Hashable {
    case empty, black, white

    public var opponent: Stone {
        switch self {
        case .black: return .white
        case .white: return .black
        case .empty: return .empty
        }
    }
}

/// A board coordinate. Column 0 is the leftmost line, row 0 the topmost one.
public struct Intersection: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let col: Int
    public let row: Int
    public init(col: Int, row: Int) { self.col = col; self.row = row }

    public static func < (a: Intersection, b: Intersection) -> Bool {
        a.row != b.row ? a.row < b.row : a.col < b.col
    }

    public var description: String { "(\(col),\(row))" }
}

/// Stones on a square board.
public struct Position: Sendable, Equatable, Hashable, CustomStringConvertible {
    public let size: Int
    private var cells: [Stone]

    public init(size: Int = 19) {
        self.size = size
        self.cells = [Stone](repeating: .empty, count: size * size)
    }

    /// Parses `size` lines of `size` characters: `.` empty, `X` black, `O` white.
    public init(parsing text: String) {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        self.size = lines.count
        self.cells = lines.flatMap { line in
            line.map { ch -> Stone in
                switch ch { case "X": return .black; case "O": return .white; default: return .empty }
            }
        }
        precondition(cells.count == size * size, "malformed board text")
    }

    public subscript(_ i: Intersection) -> Stone {
        get { cells[i.row * size + i.col] }
        set { cells[i.row * size + i.col] = newValue }
    }

    public func contains(_ i: Intersection) -> Bool {
        i.col >= 0 && i.row >= 0 && i.col < size && i.row < size
    }

    public var all: [Intersection] {
        (0..<size).flatMap { row in (0..<size).map { col in Intersection(col: col, row: row) } }
    }

    /// Occupied intersections with their colour.
    public var stones: [Intersection: Stone] {
        var out: [Intersection: Stone] = [:]
        for i in all where self[i] != .empty { out[i] = self[i] }
        return out
    }

    /// Intersections whose content differs in `other`, with the value they take there.
    public func diff(to other: Position) -> [Intersection: Stone] {
        var out: [Intersection: Stone] = [:]
        for i in all where self[i] != other[i] { out[i] = other[i] }
        return out
    }

    public func neighbours(of i: Intersection) -> [Intersection] {
        [Intersection(col: i.col - 1, row: i.row), Intersection(col: i.col + 1, row: i.row),
         Intersection(col: i.col, row: i.row - 1), Intersection(col: i.col, row: i.row + 1)]
            .filter(contains)
    }

    public var description: String {
        (0..<size).map { row in
            (0..<size).map { col -> String in
                switch self[Intersection(col: col, row: row)] {
                case .black: return "X"; case .white: return "O"; case .empty: return "."
                }
            }.joined()
        }.joined(separator: "\n")
    }
}
