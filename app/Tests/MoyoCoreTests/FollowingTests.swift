import Foundation
import Testing

@testable import MoyoCore

/// Following a game between two people on a real board, seen by Kifu. The app only
/// relays: positions go to the bridge as the phone wrote them, and the phone's word
/// that the game is over opens it as a record.
@MainActor
@Suite("Suivre une partie sur un vrai plateau")
struct FollowingTests {
    private final class Sent {
        var commands: [BridgeCommand] = []
        var names: [String] { commands.map(\.cmd) }
    }

    private func session() -> (GameSession, Sent) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let bridge = BridgeProcess()
        let sent = Sent()
        bridge.onSend = { sent.commands.append($0) }
        let session = GameSession(bridge: bridge, store: SettingsStore(defaults: defaults, key: "test.settings"))
        session.handle(.ready(katago: nil, model: nil, strategies: [], settings: [:]))
        sent.commands.removeAll()
        return (session, sent)
    }

    private func state(status: String, moveNumber: Int) throws -> BridgeEvent {
        try BridgeEvent.decode(line: """
            {"event":"state","id":2,"size":19,"stones":[],"to_play":"B","move_number":\(moveNumber),\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"\(status)","result":null,"in_sync":true}
            """)
    }

    private func line(_ text: String) -> Data { Data((text + "\n").utf8) }

    private let board = #"{"size":3,"rows":["X..","...","..O"],"status":"locked"}"#

    @Test("Sans partie en cours, connecter lance le suivi")
    func startsAtOnce() {
        let (session, sent) = session()
        session.connectPhone()
        #expect(session.isFollowing)
        #expect(!session.isConfirmingFollow)
        #expect(sent.names == ["follow_start"])
    }

    @Test("Une partie en cours fait d'abord poser la question")
    func asksFirst() throws {
        let (session, sent) = session()
        session.handle(try state(status: "playing", moveNumber: 3))
        session.connectPhone()
        #expect(session.isConfirmingFollow)
        #expect(!session.isFollowing)
        #expect(sent.names.isEmpty)
        session.saveThenFollow()
        #expect(sent.names == ["export_sgf"])
        session.exportHandled()
        #expect(session.isFollowing)
        #expect(sent.names == ["export_sgf", "follow_start"])
    }

    @Test("Chaque position part au pont telle que le téléphone l'a écrite")
    func relaysPositions() throws {
        let (session, sent) = session()
        session.connectPhone()
        session.handle(try state(status: "following", moveNumber: 0))
        session.phone.consume(line(board))
        #expect(sent.names.last == "follow_board")
        #expect(sent.commands.last?.rows == ["X..", "...", "..O"])
    }

    @Test("Hors suivi, le plateau du téléphone est ignoré")
    func ignoredOtherwise() {
        let (session, sent) = session()
        session.phone.consume(line(board))
        #expect(sent.names.isEmpty)
    }

    @Test("La fin annoncée par le téléphone ouvre la partie, la suivante repart de zéro")
    func endThenNext() throws {
        let (session, sent) = session()
        session.connectPhone()
        session.handle(try state(status: "following", moveNumber: 0))
        session.phone.consume(line(board))
        session.phone.consume(line(#"{"end":true,"result":"W+R"}"#))
        #expect(sent.names.last == "follow_end")
        #expect(sent.commands.last?.result == "W+R")
        session.handle(try state(status: "review", moveNumber: 1))
        // The end is said once; a repeat changes nothing.
        session.phone.consume(line(#"{"end":true}"#))
        #expect(sent.names.filter { $0 == "follow_end" }.count == 1)
        session.phone.consume(line(board))
        #expect(Array(sent.names.suffix(2)) == ["follow_start", "follow_board"])
    }

    @Test("Arrêter le suivi ouvre la partie suivie, ou une nouvelle partie si rien n'a été vu")
    func stopping() throws {
        let (session, sent) = session()
        session.connectPhone()
        session.handle(try state(status: "following", moveNumber: 0))
        session.stopFollowing()
        #expect(!session.isFollowing)
        #expect(sent.names.last == "new_game")

        session.connectPhone()
        session.handle(try state(status: "following", moveNumber: 12))
        session.stopFollowing()
        #expect(sent.names.last == "follow_end")
    }

    @Test("Une nouvelle partie arrête le suivi sans ouvrir de revue")
    func newGameStops() throws {
        let (session, sent) = session()
        session.connectPhone()
        session.handle(try state(status: "following", moveNumber: 12))
        session.newGame()
        #expect(!session.isFollowing)
        #expect(!sent.names.contains("follow_end"))
        #expect(sent.names.last == "new_game")
    }

    @Test("Le téléphone se présente par son nom, sans celui de l'app")
    func phoneName() {
        #expect(PhoneLink.displayName("Kifu — iPhone 2") == "iPhone 2")
        #expect(PhoneLink.displayName("GoBoardVision") == "GoBoardVision")
    }

    @Test("La fin de partie se lit, avec ou sans résultat")
    func endLine() {
        #expect(PhoneGameEnd(line: #"{"end":true,"result":"B+R"}"#) == PhoneGameEnd(result: "B+R"))
        #expect(PhoneGameEnd(line: #"{"end":true}"#) == PhoneGameEnd(result: nil))
        #expect(PhoneGameEnd(line: #"{"end":false}"#) == nil)
        #expect(PhoneGameEnd(line: #"{"size":3}"#) == nil)
    }
}
