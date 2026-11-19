import Foundation
import Testing

@testable import MoyoCore

/// A game under way, or an analysis full of variations, is not replaced without
/// asking: the same question for a new game, a record opened, a phone connected.
@MainActor
@Suite("Protection du travail en cours")
struct ReplacementTests {
    private final class Sent {
        var names: [String] = []
    }

    private func session() -> (GameSession, Sent) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let bridge = BridgeProcess()
        let sent = Sent()
        bridge.onSend = { sent.names.append($0.cmd) }
        let session = GameSession(bridge: bridge, store: SettingsStore(defaults: defaults, key: "test.settings"))
        session.handle(.ready(katago: nil, model: nil, strategies: [], settings: [:]))
        sent.names.removeAll()
        return (session, sent)
    }

    private func playing(moveNumber: Int) throws -> BridgeEvent {
        try BridgeEvent.decode(line: """
            {"event":"state","id":2,"size":9,"stones":[],"to_play":"B","move_number":\(moveNumber),\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"playing","result":null}
            """)
    }

    private func reviewing(origins: [String]) throws -> [BridgeEvent] {
        let nodes = origins.enumerated().map { index, origin in
            let parent = index == 0 ? "null" : "\(index - 1)"
            return #"{"id":\#(index),"parent":\#(parent),"move_number":\#(index),"color":null,"pass":false,"origin":"\#(origin)"}"#
        }
        let tree = try BridgeEvent.decode(line: #"{"event":"tree","id":null,"nodes":[\#(nodes.joined(separator: ","))]}"#)
        let state = try BridgeEvent.decode(line: """
            {"event":"state","id":2,"size":9,"stones":[],"to_play":"B","move_number":0,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"review","result":null,\
            "view":"analysis","node_id":0,"move_count":\(origins.count - 1)}
            """)
        return [tree, state]
    }

    private let record = SGFImport.Record(name: "partie.sgf", contents: "(;GM[1]SZ[9])")

    @Test("Sans partie en cours, une nouvelle partie part sans question")
    func nothingToProtect() throws {
        let (session, sent) = session()
        session.handle(try playing(moveNumber: 0))
        session.requestNewGame()
        #expect(!session.isConfirmingReplacement)
        #expect(sent.names == ["new_game"])
    }

    @Test("Une partie en cours contre l'IA fait poser la question")
    func gameUnderWay() throws {
        let (session, sent) = session()
        session.handle(try playing(moveNumber: 4))
        session.requestNewGame()
        #expect(session.isConfirmingReplacement)
        #expect(sent.names.isEmpty)
        session.replace()
        #expect(!session.isConfirmingReplacement)
        #expect(sent.names == ["new_game"])
    }

    @Test("Ouvrir un fichier sur une partie en cours demande aussi")
    func openingARecord() throws {
        let (session, sent) = session()
        session.handle(try playing(moveNumber: 4))
        session.requestOpening(record)
        #expect(session.isConfirmingReplacement)
        session.cancelReplacement()
        #expect(!session.isConfirmingReplacement)
        #expect(sent.names.isEmpty)
    }

    @Test("Une analyse avec des variantes ajoutées est protégée, pas une simple revue")
    func analysisVariations() throws {
        let (session, _) = session()
        for event in try reviewing(origins: ["game", "game"]) { session.handle(event) }
        #expect(!session.hasWorkToProtect)
        for event in try reviewing(origins: ["game", "game", "analysis"]) { session.handle(event) }
        #expect(session.hasWorkToProtect)
    }

    @Test("Enregistrer d'abord : la partie est remplacée une fois enregistrée")
    func saveFirst() throws {
        let (session, sent) = session()
        session.handle(try playing(moveNumber: 4))
        session.requestNewGame()
        session.saveThenReplace()
        #expect(sent.names == ["export_sgf"])
        session.recordSaved(to: URL(fileURLWithPath: "/tmp/partie.sgf"))
        session.exportHandled()
        #expect(sent.names == ["export_sgf", "new_game"])
    }

    @Test("Enregistrement annulé : rien n'est remplacé")
    func saveCancelled() throws {
        let (session, sent) = session()
        session.handle(try playing(moveNumber: 4))
        session.requestNewGame()
        session.saveThenReplace()
        session.exportHandled()
        #expect(sent.names == ["export_sgf"])
        #expect(!session.isConfirmingReplacement)
    }

    @Test("Une partie enregistrée et inchangée depuis ne fait plus poser la question")
    func savedSinceLastChange() throws {
        let (session, _) = session()
        session.handle(try playing(moveNumber: 4))
        session.recordSaved(to: URL(fileURLWithPath: "/tmp/partie.sgf"))
        #expect(!session.hasWorkToProtect)
        session.handle(try playing(moveNumber: 6))
        #expect(session.hasWorkToProtect)
    }
}
