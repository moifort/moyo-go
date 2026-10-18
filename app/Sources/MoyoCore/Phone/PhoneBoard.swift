import Foundation

/// A board position as the phone sees it: one line of JSON per change,
/// `{"size":19,"rows":["X........", ...],"status":"locked"}`, row 0 at the top and
/// column 0 on the left, the same orientation the Mac draws.
/// The format is specified in docs/protocol.md.
public struct PhoneBoard: Equatable, Sendable {
    public let size: Int
    public let stones: [Stone]
    public let status: String
    /// The rows as the phone wrote them, X for Black, O for White: what the bridge reads.
    public let rows: [String]

    public init(size: Int, stones: [Stone], status: String = "locked") {
        self.size = size
        self.stones = stones
        self.status = status
        var grid = Array(repeating: Array(repeating: Character("."), count: size), count: size)
        for stone in stones where stone.row < size && stone.col < size {
            grid[stone.row][stone.col] = stone.color == .black ? "X" : "O"
        }
        self.rows = grid.map { String($0) }
    }

    private struct Wire: Decodable {
        let size: Int
        let rows: [String]
        let status: String?
    }

    /// Decodes one line from the phone. Nil when it is not a board.
    public init?(line: String) {
        guard let data = line.data(using: .utf8),
              let wire = try? JSONDecoder().decode(Wire.self, from: data),
              wire.rows.count == wire.size,
              wire.rows.allSatisfy({ $0.count == wire.size }) else { return nil }
        var stones: [Stone] = []
        for (row, text) in wire.rows.enumerated() {
            for (col, ch) in text.enumerated() {
                switch ch {
                case "X": stones.append(Stone(row: row, col: col, color: .black))
                case "O": stones.append(Stone(row: row, col: col, color: .white))
                default: break
                }
            }
        }
        self.init(size: wire.size, stones: stones, status: wire.status ?? "locked")
    }

    public var points: Set<Point> { Set(stones.map(\.point)) }
}

/// The phone saying the game on the real board is over: `{"end":true,"result":"W+R"}`.
///
/// `result` is in SGF's own form and absent when the game simply finished: the phone
/// does not count, and the record opens without a result.
public struct PhoneGameEnd: Equatable, Sendable {
    public let result: String?

    private struct Wire: Decodable {
        let end: Bool
        let result: String?
    }

    public init(result: String?) {
        self.result = result
    }

    public init?(line: String) {
        guard let data = line.data(using: .utf8),
              let wire = try? JSONDecoder().decode(Wire.self, from: data),
              wire.end else { return nil }
        self.init(result: wire.result?.isEmpty == false ? wire.result : nil)
    }
}
