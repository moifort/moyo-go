import Foundation
import Testing

@testable import MoyoCore

/// A record double-clicked in the Finder launches the app with it. The file arrives
/// before the window exists and before KataGo is ready; it must neither be lost nor
/// be replaced by the new game the app starts on its own.
@MainActor
@Suite("Ouvrir un enregistrement au lancement")
struct RecordAtLaunchTests {
    private func session() -> GameSession {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        // The bridge is never started: `send` is a no-op, which is all these tests need.
        return GameSession(store: SettingsStore(defaults: defaults, key: "test.settings"))
    }

    private func recordFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).sgf")
        try Data("(;GM[1]FF[4]SZ[9];B[ee])".utf8).write(to: url)
        return url
    }

    private static let ready = BridgeEvent.ready(katago: nil, model: nil, strategies: [], settings: [:])

    @Test("Un fichier reçu avant le moteur attend qu'il soit prêt")
    func heldUntilReady() throws {
        let session = session()
        let url = try recordFile()
        defer { try? FileManager.default.removeItem(at: url) }

        session.openRecord(at: url)
        #expect(session.phase == .starting)
        #expect(session.recordName == url.lastPathComponent)
        #expect(session.hasRecordWaiting)
    }

    @Test("Le moteur prêt ouvre le fichier au lieu d'une nouvelle partie")
    func openedInsteadOfNewGame() throws {
        let session = session()
        let url = try recordFile()
        defer { try? FileManager.default.removeItem(at: url) }

        session.openRecord(at: url)
        session.handle(Self.ready)
        #expect(session.phase == .running)
        #expect(!session.hasRecordWaiting)
        // A new game would have cleared the name; the record is what was loaded.
        #expect(session.recordName == url.lastPathComponent)
    }

    @Test("Sans fichier, le moteur prêt lance une partie")
    func newGameOtherwise() {
        let session = session()
        session.handle(Self.ready)
        #expect(session.phase == .running)
        #expect(session.recordName == nil)
    }

    @Test("La boîte de réception ne rend un fichier qu'une fois")
    func inboxHandsOverOnce() {
        let url = URL(fileURLWithPath: "/tmp/partie.sgf")
        RecordInbox.deliver(url)
        #expect(RecordInbox.take() == url)
        #expect(RecordInbox.take() == nil)
    }
}
