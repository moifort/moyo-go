import Testing

@testable import MoyoCore

/// A translucent stone under the pointer, of the colour to play, where a click
/// would place one.
@Suite("Pierre fantôme")
struct GhostStoneTests {
    private func state(status: String, toPlay: String = "W") throws -> GameState {
        let line = """
            {"event":"state","id":2,"size":9,"stones":[{"row":4,"col":4,"color":"B"}],"to_play":"\(toPlay)",\
            "move_number":1,"last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"W","status":"\(status)","result":null}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else { throw CancellationError() }
        return state
    }

    @Test("Sur une intersection vide, la couleur au trait")
    func emptyPoint() throws {
        let ghost = try state(status: "playing").ghostStone(at: Point(row: 2, col: 3), interactive: true)
        #expect(ghost == Stone(row: 2, col: 3, color: .white))
    }

    @Test("Rien sur une pierre")
    func onAStone() throws {
        #expect(try state(status: "playing").ghostStone(at: Point(row: 4, col: 4), interactive: true) == nil)
    }

    @Test("Rien quand un clic ne poserait rien")
    func notInteractive() throws {
        #expect(try state(status: "playing").ghostStone(at: Point(row: 2, col: 3), interactive: false) == nil)
    }

    @Test("Rien pendant le comptage, où un clic marque un groupe")
    func scoring() throws {
        #expect(try state(status: "scoring").ghostStone(at: Point(row: 2, col: 3), interactive: true) == nil)
    }
}
