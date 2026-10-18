import Foundation

/// How the game ended, as chosen on the phone.
public enum GameResult: Sendable, Equatable {
    case blackResigned, whiteResigned
    /// Played to the end; the count is left to the reviewing software.
    case finished

    /// The SGF `RE` value, nil when the winner is not known.
    public var sgfValue: String? {
        switch self {
        case .blackResigned: return "W+R"
        case .whiteResigned: return "B+R"
        case .finished: return nil
        }
    }
}

/// Writes a GameRecord as a single-variation SGF file.
public enum SGFWriter {
    public static let application = "Kifu:1.0"

    public static func write(_ record: GameRecord, result: GameResult? = nil) -> String {
        var out = "(;GM[1]FF[4]CA[UTF-8]AP[\(application)]SZ[\(record.size)]DT[\(dateString(record.date))]"
        if record.handicap > 0 { out += "HA[\(record.handicap)]KM[0.5]" } else { out += "KM[6.5]" }
        if let value = result?.sgfValue { out += "RE[\(value)]" }
        if !record.setupBlack.isEmpty { out += "AB" + record.setupBlack.map(coordinate).joined() }
        if !record.setupWhite.isEmpty { out += "AW" + record.setupWhite.map(coordinate).joined() }
        for m in record.moves {
            out += ";" + (m.move.color == .black ? "B" : "W")
            out += "[" + (m.move.point.map(letters) ?? "") + "]"
            if !m.erased.isEmpty { out += "AE" + m.erased.map(coordinate).joined() }
            if m.uncertain { out += "C[ordre incertain]" }
        }
        return out + ")"
    }

    public static func letters(_ i: Intersection) -> String {
        let a = Int(UnicodeScalar("a").value)
        return String(UnicodeScalar(a + i.col)!) + String(UnicodeScalar(a + i.row)!)
    }

    static func coordinate(_ i: Intersection) -> String { "[" + letters(i) + "]" }

    static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
