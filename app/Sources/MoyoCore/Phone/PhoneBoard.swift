import Foundation

/// A board position as the phone sees it: one line of JSON per change,
/// `{"size":9,"rows":["X........", ...],"status":"locked"}`, row 0 at the top and
/// column 0 on the left, the same orientation the Mac draws.
///
/// Kifu, which records a game between two people, adds `"follow":true` — show this
/// board whatever game is open, rather than read it as moves against the AI — and
/// `"next":"B"` or `"W"`, whose turn it is. GoBoardVision sends neither.
public struct PhoneBoard: Equatable, Sendable {
    public let size: Int
    public let stones: [Stone]
    public let status: String
    public let follow: Bool
    public let next: PlayerColor?

    public init(size: Int, stones: [Stone], status: String = "locked", follow: Bool = false, next: PlayerColor? = nil) {
        self.size = size
        self.stones = stones
        self.status = status
        self.follow = follow
        self.next = next
    }

    private struct Wire: Decodable {
        let size: Int
        let rows: [String]
        let status: String?
        let follow: Bool?
        let next: String?
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
        self.init(
            size: wire.size, stones: stones, status: wire.status ?? "locked",
            follow: wire.follow ?? false, next: wire.next.flatMap(PlayerColor.init(rawValue:))
        )
    }

    public var points: Set<Point> { Set(stones.map(\.point)) }
}
