import Foundation
import Testing

@testable import MoyoCore

/// The komi on screen is the game's, as the bridge sends it, not the settings'.
@MainActor
@Suite("Komi affiché")
struct KomiTests {
    @Test("Le komi vient de l'état envoyé par le pont")
    func fromState() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let session = GameSession(bridge: BridgeProcess(), store: SettingsStore(defaults: defaults, key: "test.settings"))
        session.settings.komi = 6.5
        session.handle(try BridgeEvent.decode(line: """
            {"event":"state","id":2,"size":19,"stones":[],"to_play":"B","move_number":0,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"following","result":null,"komi":7.5}
            """))
        #expect(session.komi == 7.5)
    }
}
