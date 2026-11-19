import Foundation
import Testing

@testable import MoyoCore

/// The engine that stops mid-game is not a dead end: the screen says what happened,
/// and a new bridge can be started from it.
@MainActor
@Suite("Arrêt et relance du moteur")
struct BridgeRestartTests {
    private final class Factory {
        var made: [BridgeProcess] = []
        func make() -> BridgeProcess {
            let bridge = BridgeProcess()
            made.append(bridge)
            return bridge
        }
    }

    private func session(factory: Factory) -> GameSession {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return GameSession(
            bridge: BridgeProcess(),
            store: SettingsStore(defaults: defaults, key: "test.settings"),
            makeBridge: factory.make,
            location: { nil }
        )
    }

    @Test("Un pont qui s'arrête en cours de partie ne se dit pas « pas démarré »")
    func stoppedMidGame() {
        let session = session(factory: Factory())
        session.handle(.ready(katago: nil, model: nil, strategies: [], settings: [:]))
        session.bridgeDidStop()
        guard case .failed(let failure) = session.phase else {
            Issue.record("attendu un échec")
            return
        }
        #expect(failure.moment == .stopped)
        #expect(failure.title == "Le moteur s'est arrêté")
    }

    @Test("Un pont qui meurt avant d'être prêt n'a pas démarré")
    func neverStarted() {
        let session = session(factory: Factory())
        session.bridgeDidStop()
        guard case .failed(let failure) = session.phase else {
            Issue.record("attendu un échec")
            return
        }
        #expect(failure.moment == .startup)
        #expect(failure.title == "Le moteur n'a pas démarré")
    }

    @Test("Relancer démarre un nouveau pont, et les commandes vont à celui-là")
    func restart() {
        let factory = Factory()
        let session = session(factory: factory)
        session.handle(.ready(katago: nil, model: nil, strategies: [], settings: [:]))
        session.bridgeDidStop()
        session.restartEngine()
        #expect(factory.made.count == 1)
        var sent: [String] = []
        factory.made[0].onSend = { sent.append($0.cmd) }
        session.handle(.ready(katago: nil, model: nil, strategies: [], settings: [:]))
        #expect(sent == ["new_game"])
    }
}
