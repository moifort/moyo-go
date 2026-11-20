import Foundation

/// One game of the library, as the grid shows it without opening the record.
///
/// Everything here comes from the bridge's answer to an autosave — the position at
/// the end of the line, its length, the record's own information — or from the
/// session that played it. The record itself is the SGF next to the index; this is
/// only what is worth knowing before opening it.
public struct LibraryEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Played here, against KataGo.
        case ai
        /// Read from an SGF file.
        case record
        /// Followed on a real board, through Kifu.
        case kifu
    }

    public enum Status: String, Codable, Sendable {
        case inProgress
        case finished
    }

    public enum Analysis: Codable, Equatable, Sendable {
        case none
        case partial(done: Int, total: Int)
        case complete

        /// What the bridge counted along the line of the game.
        public init(done: Int, total: Int) {
            if total > 0, done >= total {
                self = .complete
            } else if done <= 0 {
                self = .none
            } else {
                self = .partial(done: done, total: total)
            }
        }
    }

    /// The stones at the end of the line, a character per point, top row first:
    /// `.`, `b` or `w`. Enough for a thumbnail, without an engine.
    public struct Board: Codable, Equatable, Sendable {
        public let size: Int
        public let stones: String

        public init(size: Int, stones: String) {
            self.size = size
            self.stones = stones
        }

        public static func empty(size: Int) -> Board {
            Board(size: size, stones: String(repeating: ".", count: size * size))
        }

        /// The stone on a point, if any.
        public func stone(row: Int, col: Int) -> PlayerColor? {
            let index = row * size + col
            guard row >= 0, col >= 0, row < size, col < size, index < stones.utf8.count else { return nil }
            switch stones.utf8[stones.utf8.index(stones.utf8.startIndex, offsetBy: index)] {
            case UInt8(ascii: "b"): return .black
            case UInt8(ascii: "w"): return .white
            default: return nil
            }
        }
    }

    public let id: UUID
    public var kind: Kind
    public let createdAt: Date
    /// The last time the record changed: a move, a branch, more of the analysis.
    /// The grid is sorted by it, and the card shows it.
    public var updatedAt: Date
    public var size: Int
    public var komi: Double
    public var blackName: String?
    public var whiteName: String?
    /// The player's colour, when they played: a game against KataGo.
    public var humanColor: PlayerColor?
    public var aiStrategy: String?
    public var aiSettingValue: Double?
    public var result: String?
    public var moveCount: Int
    public var status: Status
    public var analysis: Analysis
    public var finalBoard: Board
    /// SHA-256 of the text of the file it was read from: the same file opened
    /// again is the same game, and reopens with its branches and its analysis.
    public var sourceHash: String?
    /// `GN`, or `EV`, when the record has one.
    public var title: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        createdAt: Date,
        updatedAt: Date,
        size: Int,
        komi: Double,
        blackName: String? = nil,
        whiteName: String? = nil,
        humanColor: PlayerColor? = nil,
        aiStrategy: String? = nil,
        aiSettingValue: Double? = nil,
        result: String? = nil,
        moveCount: Int,
        status: Status,
        analysis: Analysis,
        finalBoard: Board,
        sourceHash: String? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.size = size
        self.komi = komi
        self.blackName = blackName
        self.whiteName = whiteName
        self.humanColor = humanColor
        self.aiStrategy = aiStrategy
        self.aiSettingValue = aiSettingValue
        self.result = result
        self.moveCount = moveCount
        self.status = status
        self.analysis = analysis
        self.finalBoard = finalBoard
        self.sourceHash = sourceHash
        self.title = title
    }

    // -- what the card says ----------------------------------------------------

    /// "Contre KataGo" for a game played here; the record's own title when it has
    /// one; otherwise the two players.
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if kind == .ai { return "Contre KataGo" }
        return "\(blackName ?? "Noir") – \(whiteName ?? "Blanc")"
    }

    /// What the line under the title says: the mode, the board, or the players.
    public var origin: String {
        switch kind {
        case .ai: return aiStrategy.map { AIMode.mode(for: $0).name } ?? "KataGo"
        case .kifu: return "Kifu · goban réel"
        case .record:
            if title != nil, blackName != nil || whiteName != nil {
                return "\(blackName ?? "Noir") vs \(whiteName ?? "Blanc")"
            }
            return "SGF importé"
        }
    }

    /// Whether the player won, when they had a colour and the game a result.
    public var won: Bool? {
        guard let humanColor, let winner = result?.first.map(String.init)?.uppercased(),
              winner == "B" || winner == "W"
        else { return nil }
        return winner == humanColor.rawValue
    }

    /// The result as the card shows it, with a decimal comma: `W+3,5`.
    public var displayResult: String? {
        result.map { $0.replacingOccurrences(of: ".", with: ",") }
    }

    /// A game against KataGo left unfinished: it can be picked up again. A game
    /// followed on a real board never can: the phone leads it.
    public var canResume: Bool { kind == .ai && status == .inProgress }

    /// Whether the analysis still has work to do. A game against KataGo under way
    /// is analysed as it is played; only a game over counts.
    public var isAnalysisIncomplete: Bool {
        if case .complete = analysis { return false }
        return !(kind == .ai && status == .inProgress)
    }

    /// Words the search box looks through.
    public var searchText: String {
        [displayTitle, blackName, whiteName, origin, title, aiStrategy.map { AIMode.mode(for: $0).name }]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
