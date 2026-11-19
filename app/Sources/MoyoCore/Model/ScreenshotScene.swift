import Foundation

/// Puts the window in a given state at launch, for the screenshots that check a
/// change: `--scene scoring`, `--scene replace`, `--scene stopped`, `--scene review`.
///
/// Like `--demo`, it goes through the session rather than the mouse. The states are
/// the bridge's own events, played once the real bridge is up and quiet.
public enum ScreenshotScene {
    public static let flag = "--scene"

    /// An intersection the board treats as hovered from the start: a screenshot has
    /// no pointer to put there.
    @MainActor static var hover: Point?

    public static func requested(in arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static let stones = """
        [{"row":2,"col":2,"color":"B"},{"row":2,"col":6,"color":"W"},{"row":6,"col":2,"color":"B"},\
        {"row":6,"col":6,"color":"W"},{"row":4,"col":4,"color":"B"},{"row":3,"col":5,"color":"W"},\
        {"row":5,"col":3,"color":"B"},{"row":5,"col":5,"color":"W"}]
        """

    private static func state(status: String, extra: String = "") -> String {
        """
        {"event":"state","id":null,"size":9,"stones":\(stones),"to_play":"B","move_number":8,\
        "last_move":{"row":5,"col":5},"captures":{"by_black":1,"by_white":0},"score_history":[],\
        "score_lead":1.5,"human_color":"B","status":"\(status)","result":null,"komi":6.5\(extra)}
        """
    }

    @MainActor
    public static func run(_ scene: String, on session: GameSession) async {
        let deadline = Date().addingTimeInterval(120)
        while session.state == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
        try? await Task.sleep(for: .seconds(2))
        func play(_ line: String) {
            if let event = try? BridgeEvent.decode(line: line) { session.handle(event) }
        }
        switch scene {
        case "scoring":
            play(state(status: "scoring", extra: """
                ,"scoring":{"black":12.0,"white":10.5,"komi":6.5,"territory":{"B":11,"W":4},\
                "result":"B+1.5","points":[],"dead_stones":[]}
                """))
        case "replace":
            play(state(status: "playing"))
            session.requestNewGame()
        case "stopped":
            play(state(status: "playing"))
            session.bridgeDidStop()
        case "ghost":
            hover = Point(row: 3, col: 3)
            play(state(status: "playing"))
        default:
            play(state(status: "playing"))
        }
    }
}
