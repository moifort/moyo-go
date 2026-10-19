import Foundation

public enum PlayerColor: String, Codable, Sendable, Hashable {
    case black = "B"
    case white = "W"

    public var opponent: PlayerColor { self == .black ? .white : .black }
}

public struct Point: Codable, Sendable, Hashable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

public struct Stone: Codable, Sendable, Hashable {
    public let row: Int
    public let col: Int
    public let color: PlayerColor

    public var point: Point { Point(row: row, col: col) }
}

public struct Captures: Codable, Sendable, Hashable {
    public let byBlack: Int
    public let byWhite: Int

    public init(byBlack: Int, byWhite: Int) {
        self.byBlack = byBlack
        self.byWhite = byWhite
    }
}

/// One value from KaTrain's AI settings, which mix numbers, flags and text.
///
/// Decoding them into a single concrete type would fail on the first boolean, so
/// each value keeps its own shape and callers ask for what they need.
public enum SettingValue: Codable, Sendable, Hashable {
    case number(Double)
    case flag(Bool)
    case text(String)
    case unsupported

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .flag(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .text(value)
        } else {
            self = .unsupported
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .flag(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .unsupported: try container.encodeNil()
        }
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

public enum GameStatus: String, Codable, Sendable {
    case playing
    /// Both players have passed; the dead stones are being agreed on.
    case scoring
    case finished
    /// A record is being read rather than played: nothing on the board can be moved.
    case review
    /// A game between two people on a real board, seen by the phone. Nothing is
    /// played on the Mac: the board follows the phone, and KataGo analyses.
    case following
}

/// KataGo's first choice at the position on screen.
///
/// `pointsLost` is what the move actually played gives away against it. Nothing
/// displays it yet — the board shows a single mark and no figure — but it travels
/// with the point because it costs nothing and is the whole of a teaching mode.
public struct BestMove: Codable, Sendable, Hashable {
    public let row: Int
    public let col: Int
    public let pointsLost: Double

    public init(row: Int, col: Int, pointsLost: Double) {
        self.row = row
        self.col = col
        self.pointsLost = pointsLost
    }

    public var point: Point { Point(row: row, col: col) }
}

/// The best move inside the zone of the fight, read by KataGo kept in that zone.
///
/// `pointsLost` is what playing it costs against the best move on the whole board.
/// nil while the whole-board analysis has not come back, and always nil for the
/// moves of a local sequence being walked, which nobody has measured.
public struct LocalMove: Codable, Sendable, Hashable {
    public let row: Int
    public let col: Int
    public let pointsLost: Double?

    public init(row: Int, col: Int, pointsLost: Double?) {
        self.row = row
        self.col = col
        self.pointsLost = pointsLost
    }

    public var point: Point { Point(row: row, col: col) }

    /// What the local move costs, in words; nil when the bridge could not say.
    ///
    /// Under a tenth of a point the two moves are as good as each other, and a
    /// figure of "0,0 point" would read as a rounding mistake.
    public var costLabel: String? {
        guard let pointsLost else { return nil }
        let rounded = (pointsLost * 10).rounded() / 10
        guard rounded >= 0.1 else { return "aussi bon que le meilleur coup" }
        let figure = String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
        return "coûte \(figure) point\(rounded >= 2 ? "s" : "")"
    }
}

/// The zone the local reading is kept in, bounds inclusive: drawn by the bridge
/// around the last move, or by the player across the board.
public struct LocalZone: Codable, Sendable, Hashable {
    public let top: Int
    public let left: Int
    public let bottom: Int
    public let right: Int

    public init(top: Int, left: Int, bottom: Int, right: Int) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// The rectangle between two corners of a drag, whichever way it went.
    public init(spanning a: Point, _ b: Point) {
        self.init(
            top: min(a.row, b.row), left: min(a.col, b.col),
            bottom: max(a.row, b.row), right: max(a.col, b.col)
        )
    }
}

/// Whose line a variation follows.
public enum VariationKind: String, Codable, Sendable {
    /// KataGo's own continuation, over the whole board.
    case best
    /// The sequence kept inside the zone of the fight.
    case local
}

/// Which side of the toggle at the top of the window the player is on.
public enum GameView: String, Codable, Sendable {
    /// The game itself: played against the AI, or followed on the real board.
    case live
    /// The tree: stones placed by hand, both colours, KataGo reading each position.
    case analysis
}

/// Where an arrow key leads in the tree.
public enum TreeDestination: String, Codable, Sendable {
    case back, forward, start, end
    case previousSibling = "previous_sibling"
    case nextSibling = "next_sibling"
    /// The move of the game the branch on screen starts from.
    case game
}

/// One position of the tree the sidebar draws, as the bridge numbers it.
public struct TreeNode: Codable, Sendable, Hashable, Identifiable {
    public enum Origin: String, Codable, Sendable {
        /// The line of the game: the record's main line, or the moves played.
        case game
        /// A branch the record came with.
        case record
        /// A stone the player placed in analysis, or a move kept to reach one.
        case analysis
        /// A move of KataGo's line being walked, gone once the walk is left.
        case preview
    }

    public let id: Int
    /// nil for the root, the empty board or its setup.
    public let parent: Int?
    /// nil for the root.
    public let color: PlayerColor?
    public let row: Int?
    public let col: Int?
    public let pass: Bool
    public let origin: Origin

    public init(
        id: Int, parent: Int?, color: PlayerColor?, row: Int? = nil, col: Int? = nil,
        pass: Bool = false, origin: Origin
    ) {
        self.id = id
        self.parent = parent
        self.color = color
        self.row = row
        self.col = col
        self.pass = pass
        self.origin = origin
    }
}

/// What the record says about the game it holds. Every field may be absent.
public struct GameInfo: Codable, Sendable, Hashable {
    public let blackName: String?
    public let whiteName: String?
    public let blackRank: String?
    public let whiteRank: String?
    public let result: String?
    public let date: String?
    public let event: String?

    /// A player's name and rank on one line, or nil when the record says neither.
    public func label(for color: PlayerColor) -> String? {
        let name = color == .black ? blackName : whiteName
        let rank = color == .black ? blackRank : whiteRank
        switch (name, rank) {
        case (let name?, let rank?): return "\(name) \(rank)"
        case (let name?, nil): return name
        case (nil, let rank?): return rank
        case (nil, nil): return nil
        }
    }
}

public struct TerritoryPoint: Codable, Sendable, Hashable {
    public let row: Int
    public let col: Int
    public let color: PlayerColor

    public var point: Point { Point(row: row, col: col) }
}

/// The count as it stands, recomputed by the bridge on every change.
public struct ScoringDetail: Codable, Sendable {
    public let black: Double
    public let white: Double
    public let komi: Double
    public let territory: [String: Int]
    /// Stones captured, by capturing player. Absent under area scoring.
    public let prisoners: [String: Int]?
    /// Living stones on the board, by colour. Only under area scoring.
    public let stones: [String: Int]?
    public let result: String
    public let points: [TerritoryPoint]
    public let deadStones: [Point]

    public func territory(for color: PlayerColor) -> Int {
        territory[color.rawValue] ?? 0
    }

    public func prisoners(for color: PlayerColor) -> Int? {
        prisoners?[color.rawValue]
    }

    public func stones(for color: PlayerColor) -> Int? {
        stones?[color.rawValue]
    }

    public func total(for color: PlayerColor) -> Double {
        color == .black ? black : white
    }

    public var deadPoints: Set<Point> { Set(deadStones) }

    /// The winner and by how much, or nil for a draw.
    public var outcome: (winner: PlayerColor, margin: Double)? {
        let margin = abs(black - white)
        guard margin > 0 else { return nil }
        return (black > white ? .black : .white, margin)
    }
}

/// The score at any moment of a game, as the bridge estimates it.
///
/// Counted like a finished game once nearly every point has a settled owner
/// (`count`); before that, KataGo's own lead to the half point. Either way the
/// board marks the points KataGo already gives to one side.
public struct ScoreEstimate: Codable, Sendable {
    /// Black's lead, from Black's point of view. Nil until KataGo has given one.
    public let lead: Double?
    public let points: [TerritoryPoint]
    public let deadStones: [Point]
    /// The count, when the position is settled enough to have one.
    public let count: ScoringDetail?

    public var deadPoints: Set<Point> { Set(deadStones) }
}

/// The whole board state, as the bridge sees it. The app never derives it.
public struct GameState: Codable, Sendable {
    public let size: Int
    public let stones: [Stone]
    public let toPlay: PlayerColor
    public let moveNumber: Int
    public let lastMove: Point?
    public let captures: Captures
    public let scoreHistory: [Double?]
    public let scoreLead: Double?
    public let humanColor: PlayerColor
    public let status: GameStatus
    public let result: String?
    public let scoring: ScoringDetail?
    /// The score as KataGo's ownership map has it, while the player asks for it.
    /// Nil until that map is back, and once the game is counted for real.
    public let estimate: ScoreEstimate?
    /// The player asked for the estimate. Absent from an older bridge.
    public let estimating: Bool?
    /// The AI mode currently in force, as the bridge sees it.
    public let aiStrategy: String?
    public let aiSettings: [String: SettingValue]?

    // -- review only; all nil while a game is being played

    /// Moves in the record's main line. `moveNumber` is a position within it.
    public let moveCount: Int?
    public let gameInfo: GameInfo?
    /// How far down a continuation we have walked, 0 on the record itself.
    public let variationDepth: Int?
    /// Which continuation is being walked; nil on the record itself.
    public let variationKind: VariationKind?
    /// nil until the analysis for this position comes back.
    public let bestMove: BestMove?
    /// nil until the local reading comes back, and when there is no fight to read.
    public let localMove: LocalMove?
    /// Sent before the local reading, so the player sees where it is looking.
    public let localZone: LocalZone?
    /// Whether the zone is the player's own rather than the bridge's.
    public let localZoneDrawn: Bool?
    /// KataGo is still reading the zone on screen. A press on ⌥→ meanwhile is kept
    /// by the bridge and played once the reading lands.
    public let localPending: Bool?
    /// ⌥→ was pressed before the reading came back; the first move is on its way.
    public let localWanted: Bool?

    // -- the analysis tree; absent from an older bridge

    /// Which side of the toggle the player is on.
    public let view: GameView?
    /// The node on screen, as numbered in the last `tree` event.
    public let nodeId: Int?
    /// The head of the game played or followed; nil for a record alone or a game over.
    public let liveNodeId: Int?

    // -- following only

    /// False when the last position the phone sent could not be reached by any move.
    public let inSync: Bool?
    /// KataGo analyses the game followed; the suggestions travel with the state.
    public let analysis: Bool?

    public var isFollowing: Bool { status == .following }

    public var isReadingLocally: Bool { localPending == true }

    /// A record with no game behind it: no live view to go back to.
    public var isReviewing: Bool { status == .review }

    /// The board shows the tree: stones are placed by hand, both colours.
    public var isAnalysing: Bool { view == .analysis || status == .review }

    /// There is a game to go back to: played against the AI, or followed. A game
    /// over has none — its end is the end of the line in analysis.
    public var hasLiveGame: Bool { status == .playing || status == .scoring || status == .following }

    public var isHumanTurn: Bool { status == .playing && toPlay == humanColor }

    /// Who won, when the game ended on a resignation rather than a count.
    ///
    /// Read off the result the bridge sends, in SGF's own form: `W+R` is White
    /// winning by resignation.
    public var winnerByResignation: PlayerColor? {
        guard status == .finished, let result, result.hasSuffix("+R") else { return nil }
        return PlayerColor(rawValue: String(result.prefix(1)))
    }

    /// Points the player can act on: play a stone, or mark a group dead.
    ///
    /// In analysis every point takes a stone; following, a click is a question asked
    /// of the position, and opens the analysis.
    public var acceptsClicks: Bool {
        isAnalysing || status == .playing || status == .scoring || status == .following
    }
}

public enum BridgeEvent: Sendable {
    case ready(katago: String?, model: String?, strategies: [String], settings: [String: [String: SettingValue]])
    case state(id: Int?, GameState)
    case thinking(Bool)
    case score(moveNumber: Int, scoreLead: Double)
    /// How much of a record under review KataGo has finished chewing through.
    case analysisProgress(done: Int, total: Int)
    /// The game as SGF text, in answer to `export_sgf`.
    case sgf(id: Int?, contents: String)
    /// A record analysed to the end, analysis included, for the app to write over
    /// the file it came from. `id` is the `load_sgf` that opened it.
    case recordAnalysed(id: Int?, contents: String)
    /// The tree the sidebar draws, sent whenever its shape changes. Root first,
    /// each parent before its children, children in the order to draw them.
    case tree([TreeNode])
    case failure(id: Int?, code: String, message: String)
    case engineFailed(message: String)

    /// Events the bridge may add later. Ignoring them keeps an older app from
    /// choking on a newer bridge.
    case unknown(String)
}

extension BridgeEvent: Decodable {
    private enum Keys: String, CodingKey {
        case event, id, katago, model, value, moveNumber, scoreLead, code, message
        case strategies, aiSettings, done, total, contents, nodes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let name = try container.decode(String.self, forKey: .event)
        let id = try container.decodeIfPresent(Int.self, forKey: .id)

        switch name {
        case "ready":
            self = .ready(
                katago: try container.decodeIfPresent(String.self, forKey: .katago),
                model: try container.decodeIfPresent(String.self, forKey: .model),
                strategies: try container.decodeIfPresent([String].self, forKey: .strategies) ?? [],
                settings: try container.decodeIfPresent(
                    [String: [String: SettingValue]].self, forKey: .aiSettings
                ) ?? [:]
            )
        case "state":
            self = .state(id: id, try GameState(from: decoder))
        case "thinking":
            self = .thinking(try container.decode(Bool.self, forKey: .value))
        case "score":
            self = .score(
                moveNumber: try container.decode(Int.self, forKey: .moveNumber),
                scoreLead: try container.decode(Double.self, forKey: .scoreLead)
            )
        case "analysis_progress":
            self = .analysisProgress(
                done: try container.decode(Int.self, forKey: .done),
                total: try container.decode(Int.self, forKey: .total)
            )
        case "sgf":
            self = .sgf(id: id, contents: try container.decode(String.self, forKey: .contents))
        case "record_analysed":
            self = .recordAnalysed(id: id, contents: try container.decode(String.self, forKey: .contents))
        case "tree":
            self = .tree(try container.decode([TreeNode].self, forKey: .nodes))
        case "error":
            self = .failure(
                id: id,
                code: try container.decode(String.self, forKey: .code),
                message: try container.decode(String.self, forKey: .message)
            )
        case "engine_failed":
            self = .engineFailed(message: try container.decode(String.self, forKey: .message))
        default:
            self = .unknown(name)
        }
    }

    public static func decode(line: String) throws -> BridgeEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BridgeEvent.self, from: Data(line.utf8))
    }
}
