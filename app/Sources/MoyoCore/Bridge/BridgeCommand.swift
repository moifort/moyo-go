import Foundation

/// A command sent to the bridge. Unset fields are omitted from the JSON.
public struct BridgeCommand: Encodable, Sendable {
    public let id: Int
    public let cmd: String

    var size: Int?
    var komi: Double?
    var rules: String?
    var humanColor: PlayerColor?
    var aiStrategy: String?
    var aiSettings: [String: Double]?
    var row: Int?
    var col: Int?
    /// The record's file name, for the window title. The bridge never opens it.
    var name: String?
    var contents: String?
    var moveNumber: Int?
    var step: Int?
    var blackName: String?
    var whiteName: String?

    public static func newGame(
        id: Int,
        size: Int,
        komi: Double,
        rules: String,
        humanColor: PlayerColor,
        aiStrategy: String,
        aiSettings: [String: Double]
    ) -> BridgeCommand {
        BridgeCommand(
            id: id, cmd: "new_game", size: size, komi: komi, rules: rules,
            humanColor: humanColor, aiStrategy: aiStrategy, aiSettings: aiSettings
        )
    }

    public static func play(id: Int, row: Int, col: Int) -> BridgeCommand {
        BridgeCommand(id: id, cmd: "play", row: row, col: col)
    }

    /// Switches the AI mode in the middle of a game.
    public static func setAI(id: Int, strategy: String, settings: [String: Double]) -> BridgeCommand {
        BridgeCommand(id: id, cmd: "set_ai", aiStrategy: strategy, aiSettings: settings)
    }

    /// Hands a record over as text, not as a path.
    ///
    /// The sandbox grants the window access to the file the player chose, not the
    /// child process; and `shims/chardet` is deliberately too modest to guess an
    /// encoding. Decoding happens here, where AppKit does it well.
    public static func loadSGF(id: Int, name: String, contents: String) -> BridgeCommand {
        BridgeCommand(id: id, cmd: "load_sgf", name: name, contents: contents)
    }

    /// Asks for the game as SGF text, answered by an `sgf` event.
    ///
    /// The names sign a game against the AI; a record under review keeps its own,
    /// and the bridge ignores these.
    public static func exportSGF(id: Int, blackName: String?, whiteName: String?) -> BridgeCommand {
        BridgeCommand(id: id, cmd: "export_sgf", blackName: blackName, whiteName: whiteName)
    }

    /// Jumps to a position in the record. The bridge clamps anything out of range.
    public static func goto(id: Int, moveNumber: Int) -> BridgeCommand {
        BridgeCommand(id: id, cmd: "goto", moveNumber: moveNumber)
    }

    /// Walks KataGo's own continuation: +1 adds a move, -1 takes one back.
    public static func variation(id: Int, step: Int) -> BridgeCommand {
        BridgeCommand(id: id, cmd: "variation", step: step)
    }

    public static func toggleDead(id: Int, row: Int, col: Int) -> BridgeCommand {
        BridgeCommand(id: id, cmd: "toggle_dead", row: row, col: col)
    }

    public static func acceptScore(id: Int) -> BridgeCommand { BridgeCommand(id: id, cmd: "accept_score") }
    public static func resumeGame(id: Int) -> BridgeCommand { BridgeCommand(id: id, cmd: "resume_game") }

    public static func pass(id: Int) -> BridgeCommand { BridgeCommand(id: id, cmd: "pass") }
    public static func undo(id: Int) -> BridgeCommand { BridgeCommand(id: id, cmd: "undo") }
    public static func resign(id: Int) -> BridgeCommand { BridgeCommand(id: id, cmd: "resign") }
    public static func state(id: Int) -> BridgeCommand { BridgeCommand(id: id, cmd: "state") }
    public static func quit(id: Int) -> BridgeCommand { BridgeCommand(id: id, cmd: "quit") }

    /// One JSON object followed by a newline, which is what the bridge reads.
    public func encodedLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
