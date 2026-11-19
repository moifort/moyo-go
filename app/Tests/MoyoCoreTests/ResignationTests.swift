import Foundation
import Testing

@testable import MoyoCore

@Suite("Fin de partie par abandon")
struct ResignationTests {
    private func state(status: String, result: String?) throws -> GameState {
        let result = result.map { "\"\($0)\"" } ?? "null"
        let line = """
            {"event":"state","id":2,"size":9,"stones":[],"to_play":"B","move_number":0,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"\(status)","result":\(result)}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            throw CancellationError()
        }
        return state
    }

    @Test("Un abandon désigne le vainqueur")
    func winner() throws {
        #expect(try state(status: "finished", result: "W+R").winnerByResignation == .white)
        #expect(try state(status: "finished", result: "B+R").winnerByResignation == .black)
    }

    @Test("Une partie comptée n'est pas un abandon")
    func counted() throws {
        #expect(try state(status: "finished", result: "B+12.5").winnerByResignation == nil)
    }

    @Test("Une partie en cours n'a pas de vainqueur")
    func playing() throws {
        #expect(try state(status: "playing", result: nil).winnerByResignation == nil)
    }

    @Test("Le joueur ne peut plus agir sur une partie abandonnée")
    func noMoreTurns() throws {
        #expect(try state(status: "finished", result: "W+R").isHumanTurn == false)
    }
}

/// The menu and the sidebar ask the same question before giving up the game.
@MainActor
@Suite("Confirmation de l'abandon")
struct ResignationConfirmationTests {
    @Test("Demander l'abandon pose la question sans rien envoyer")
    func asksFirst() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let bridge = BridgeProcess()
        var sent: [String] = []
        bridge.onSend = { sent.append($0.cmd) }
        let session = GameSession(bridge: bridge, store: SettingsStore(defaults: defaults, key: "test.settings"))
        session.handle(.ready(katago: nil, model: nil, strategies: [], settings: [:]))
        session.handle(try BridgeEvent.decode(line: """
            {"event":"state","id":2,"size":9,"stones":[],"to_play":"B","move_number":3,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"playing","result":null}
            """))
        sent.removeAll()
        session.requestResignation()
        #expect(session.isConfirmingResignation)
        #expect(sent.isEmpty)
        session.resign()
        #expect(!session.isConfirmingResignation)
        #expect(sent == ["resign"])
    }
}
