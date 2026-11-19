import Foundation
import Testing

@testable import MoyoCore

/// The bridge says what went wrong with a code; the words, and the title they go
/// under, are the app's. A refused action is not a record that will not open.
@MainActor
@Suite("Erreurs du pont")
struct SessionErrorTests {
    private func session() -> GameSession {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let session = GameSession(
            bridge: BridgeProcess(), store: SettingsStore(defaults: defaults, key: "test.settings")
        )
        session.handle(.ready(katago: nil, model: nil, strategies: [], settings: [:]))
        return session
    }

    @Test("Une action refusée porte son propre titre, en français")
    func refusedAction() {
        let session = session()
        session.handle(.failure(id: 3, code: "not_playing", message: "the game is over"))
        #expect(session.lastError?.kind == .refused)
        #expect(session.lastError?.title == "Action impossible")
        #expect(session.lastError?.message.contains("game") == false)
    }

    @Test("Chaque code connu a un texte en français, jamais celui du pont")
    func everyCodeIsTranslated() {
        let english = ["the game is over", "it is the AI's turn", "there is no stone there", "engine not started"]
        for code in SessionError.knownCodes {
            let error = SessionError.fromBridge(code: code, message: "the game is over")
            if let error {
                #expect(!english.contains(error.message), "code \(code)")
                #expect(!error.message.isEmpty, "code \(code)")
            }
        }
    }

    @Test("Une erreur interne reste générique et ne montre pas l'exception")
    func internalError() {
        let session = session()
        session.handle(.failure(id: 4, code: "internal", message: "KeyError: 'policy'"))
        #expect(session.lastError?.kind == .engine)
        #expect(session.lastError?.title == "Erreur du moteur")
        #expect(session.lastError?.message.contains("KeyError") == false)
    }

    @Test("Un code inconnu est traité comme une erreur interne")
    func unknownCode() {
        let error = SessionError.fromBridge(code: "brand_new", message: "something")
        #expect(error?.kind == .engine)
        #expect(error?.message.contains("something") == false)
    }

    @Test("Un SGF refusé dit que la partie n'a pas pu être ouverte")
    func badRecord() {
        let error = SessionError.fromBridge(code: "bad_sgf", message: "le fichier est vide")
        #expect(error?.kind == .opening)
        #expect(error?.title == "Cette partie n'a pas pu être ouverte")
    }

    @Test("Une touche pressée un instant trop tôt n'ouvre aucune alerte", arguments: [
        "illegal_move", "no_variation", "not_following", "nothing_to_undo", "no_node", "not_now", "not_your_turn",
    ])
    func silent(code: String) {
        let session = session()
        session.handle(.failure(id: 5, code: code, message: "whatever"))
        #expect(session.lastError == nil)
    }
}
