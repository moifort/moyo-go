import Foundation
import Testing

@testable import MoyoCore

/// Once KataGo has analysed every position of a record, the bridge hands it back
/// with the analysis and the app writes it over the file it opened. Opened again,
/// the record is read instead of analysed a second time.
@MainActor
@Suite("Analyse conservée dans le fichier ouvert")
struct AnalysedRecordTests {
    private static let original = "(;GM[1]FF[4]SZ[9];B[ee])"
    private static let analysed = "(;GM[1]FF[4]CA[UTF-8]SZ[9]KTV[1.0];B[ee]KT[a][b][c])"
    private static let ready = BridgeEvent.ready(katago: nil, model: nil, strategies: [], settings: [:])

    private func session() -> GameSession {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return GameSession(store: SettingsStore(defaults: defaults, key: "test.settings"))
    }

    private func recordFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).sgf")
        try Data(Self.original.utf8).write(to: url)
        return url
    }

    private func opened(_ url: URL) -> GameSession {
        let session = session()
        session.handle(Self.ready)
        session.openRecord(at: url)
        return session
    }

    private func contents(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @Test("Le pont rend l'enregistrement analysé, avec la commande qui l'a ouvert")
    func event() throws {
        let line = #"{"event":"record_analysed","id":4,"contents":"(;GM[1])"}"#
        guard case .recordAnalysed(let id, let contents) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement record_analysed")
            return
        }
        #expect(id == 4)
        #expect(contents == "(;GM[1])")
    }

    @Test("Le fichier ouvert reçoit l'analyse")
    func written() throws {
        let url = try recordFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let session = opened(url)

        let command = try #require(session.openedRecordCommand)
        session.handle(.recordAnalysed(id: command, contents: Self.analysed))
        #expect(try contents(url) == Self.analysed)
        #expect(session.lastErrorMessage == nil)
    }

    @Test("La réponse pour un enregistrement remplacé depuis ne touche à rien")
    func staleAnswer() throws {
        let url = try recordFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let session = opened(url)

        let command = try #require(session.openedRecordCommand)
        session.handle(.recordAnalysed(id: command - 1, contents: Self.analysed))
        #expect(try contents(url) == Self.original)
    }

    @Test("Une nouvelle partie laisse le fichier tranquille")
    func newGame() throws {
        let url = try recordFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let session = opened(url)
        let command = try #require(session.openedRecordCommand)

        session.newGame()
        session.handle(.recordAnalysed(id: command, contents: Self.analysed))
        #expect(session.openedRecordCommand == nil)
        #expect(try contents(url) == Self.original)
    }

    @Test("Un fichier modifié ailleurs depuis son ouverture n'est pas écrasé")
    func changedOnDisk() throws {
        let url = try recordFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let session = opened(url)

        let edited = "(;GM[1]FF[4]SZ[9];B[ee];W[cc])"
        try Data(edited.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: url.path
        )
        let command = try #require(session.openedRecordCommand)
        session.handle(.recordAnalysed(id: command, contents: Self.analysed))
        #expect(try contents(url) == edited)
        #expect(session.lastErrorMessage == SGFExport.Failure.changedOnDisk(url.lastPathComponent).errorDescription)
    }

    @Test("Un enregistrement fait à la main sur le même fichier l'emporte")
    func savedByThePlayer() throws {
        let url = try recordFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let session = opened(url)
        let command = try #require(session.openedRecordCommand)

        let saved = "(;GM[1]FF[4]SZ[9];B[ee](;W[cc])(;W[gg]))"
        try SGFExport.write(saved, to: url)
        session.recordSaved(to: url)
        session.handle(.recordAnalysed(id: command, contents: Self.analysed))
        #expect(try contents(url) == saved)
        #expect(session.lastErrorMessage == nil)
    }
}
