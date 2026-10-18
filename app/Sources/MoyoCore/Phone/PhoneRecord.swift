import Foundation

/// The board a phone asks the Mac to follow, written as a record of one position.
///
/// Only the stones are known, not the moves that put them there, so they go in as
/// setup stones and the record opens on that position, with whose turn it is.
public enum PhoneRecord {
    public static func sgf(_ board: PhoneBoard, komi: Double, event: String) -> String {
        var text = "(;GM[1]FF[4]CA[UTF-8]SZ[\(board.size)]KM[\(komi)]EV[\(escaped(event))]"
        if let next = board.next { text += "PL[\(next.rawValue)]" }
        for color in [PlayerColor.black, .white] {
            let points = board.stones.filter { $0.color == color }
                .map { "[\(letter($0.col))\(letter($0.row))]" }
            if !points.isEmpty { text += (color == .black ? "AB" : "AW") + points.joined() }
        }
        return text + ")"
    }

    /// SGF letters: "a" is the leftmost column and the top row.
    private static func letter(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(ascii: "a") + UInt8(index)))
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "]", with: "\\]")
    }
}
