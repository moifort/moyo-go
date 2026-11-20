import Foundation
import Testing

@testable import MoyoCore

/// Every game is kept as it goes: nothing on screen is replaced without being
/// written first, and a game against KataGo left unfinished is picked up again.
@MainActor
@Suite("Bibliothèque des parties")
struct LibraryTests {
    private final class Sent {
        var commands: [BridgeCommand] = []
        var names: [String] { commands.map(\.cmd) }
    }

    private func session(library: GameLibrary = GameLibrary(directory: nil)) -> (GameSession, Sent) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let bridge = BridgeProcess()
        let sent = Sent()
        bridge.onSend = { sent.commands.append($0) }
        let session = GameSession(
            bridge: bridge, store: SettingsStore(defaults: defaults, key: "test.settings"), library: library
        )
        session.handle(.ready(katago: nil, model: nil, strategies: [], settings: [:]))
        sent.commands.removeAll()
        return (session, sent)
    }

    private func state(_ status: String = "playing", moveNumber: Int, human: String = "B") throws -> BridgeEvent {
        try BridgeEvent.decode(line: """
            {"event":"state","id":2,"size":9,"stones":[{"row":4,"col":4,"color":"B"}],"to_play":"W",\
            "move_number":\(moveNumber),"last_move":null,"captures":{"by_black":0,"by_white":0},\
            "score_history":[],"score_lead":null,"human_color":"\(human)","status":"\(status)",\
            "result":null,"ai_strategy":"ai:human"}
            """)
    }

    private func answer(
        _ contents: String, reason: SGFAnswer.Reason = .autosave, result: String? = nil, moves: Int = 3,
        analysed: (Int, Int) = (4, 4)
    ) throws -> SGFAnswer {
        let info = result.map { #","game_info":{"result":"\#($0)"}"# } ?? ""
        let line = """
            {"event":"sgf","id":0,"contents":\(String(reflecting: contents)),"reason":"\(reason.rawValue)",\
            "final_board":{"size":9,"stones":"\(String(repeating: ".", count: 40))b\(String(repeating: ".", count: 40))"},\
            "move_count":\(moves),"analysed":{"done":\(analysed.0),"total":\(analysed.1)}\(info)}
            """
        guard case .sgf(_, let parsed) = try BridgeEvent.decode(line: line) else { throw CocoaError(.coderInvalidValue) }
        return parsed
    }

    /// Plays the bridge's part for the last autosave sent.
    private func answerAutosave(_ session: GameSession, _ sent: Sent, _ contents: String, result: String? = nil) throws {
        let command = try #require(sent.commands.last { $0.cmd == "export_sgf" })
        #expect(command.reason == "autosave")
        session.handle(.sgf(id: command.id, try answer(contents, result: result)))
    }

    private let record = SGFImport.Record(name: "partie.sgf", contents: "(;GM[1]SZ[9];B[ee];W[cc])")

    // -- replacing the work ---------------------------------------------------------

    @Test("Une nouvelle partie remplace la partie en cours sans question, après l'avoir gardée")
    func replacesAfterKeeping() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 4))
        session.requestNewGame()
        #expect(sent.names == ["export_sgf", "new_game"])
    }

    @Test("Une partie vide n'est pas gardée")
    func emptyGameNotKept() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 0))
        session.requestNewGame()
        #expect(sent.names == ["new_game"])
        #expect(session.library.entries.isEmpty)
    }

    @Test("Ouvrir un fichier sur une partie en cours la garde d'abord")
    func openingKeepsTheGame() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 4))
        session.requestOpening(record)
        #expect(sent.names == ["export_sgf", "load_sgf"])
        #expect(!session.isShowingLibrary)
    }

    @Test("Suivre un goban garde la partie en cours, puis en commence une autre")
    func followingKeepsTheGame() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 3))
        let before = session.currentEntryID
        session.connectPhone()
        #expect(session.isChoosingPhone)
        session.follow(phone: "iPhone 2")
        #expect(sent.names == ["export_sgf", "follow_start"])
        #expect(session.currentEntryID != before)
    }

    // -- the answers ------------------------------------------------------------------

    @Test("La réponse d'un autosave va dans la bibliothèque, pas au panneau")
    func autosaveGoesToTheLibrary() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 3, human: "W"))
        session.flushAutosave()
        try answerAutosave(session, sent, "(;GM[1]SZ[9];B[ee];W[cc];B[gg])")
        #expect(session.pendingExport == nil)
        let entry = try #require(session.library.entries.first)
        #expect(entry.id == session.currentEntryID)
        #expect(entry.kind == .ai)
        #expect(entry.status == .inProgress)
        #expect(entry.humanColor == .white)
        #expect(entry.aiStrategy == "ai:human")
        #expect(entry.moveCount == 3)
        #expect(entry.finalBoard.stone(row: 4, col: 4) == .black)
        #expect(entry.analysis == .complete)
        #expect(entry.canResume)
        #expect(session.library.contents(of: entry.id) == "(;GM[1]SZ[9];B[ee];W[cc];B[gg])")
    }

    @Test("La réponse du ⌘S va au panneau, pas dans la bibliothèque")
    func exportGoesToThePanel() throws {
        let (session, _) = session()
        session.handle(try state(moveNumber: 3))
        session.handle(.sgf(id: 9, try answer("(;GM[1])", reason: .export)))
        #expect(session.pendingExport?.contents == "(;GM[1])")
        #expect(session.library.entries.isEmpty)
    }

    @Test("Un texte inchangé ne fait pas remonter la partie")
    func unchangedKeepsItsDate() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 3))
        session.flushAutosave()
        try answerAutosave(session, sent, "(;GM[1]SZ[9];B[ee])")
        let first = try #require(session.library.entries.first?.updatedAt)
        session.handle(try state(moveNumber: 4))
        session.flushAutosave()
        try answerAutosave(session, sent, "(;GM[1]SZ[9];B[ee])")
        #expect(session.library.entries.first?.updatedAt == first)
    }

    @Test("Rien n'est redemandé tant que la partie n'a pas changé")
    func nothingNewNothingSent() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 3))
        #expect(session.flushAutosave())
        #expect(!session.flushAutosave())
        #expect(sent.names == ["export_sgf"])
    }

    @Test("La fin de partie est gardée sur-le-champ")
    func endOfGameAtOnce() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 3))
        #expect(sent.names.isEmpty)
        session.handle(try state("finished", moveNumber: 3))
        #expect(sent.names == ["export_sgf"])
        try answerAutosave(session, sent, "(;GM[1]RE[W+R])", result: "W+R")
        let entry = try #require(session.library.entries.first)
        #expect(entry.status == .finished)
        #expect(entry.result == "W+R")
        #expect(entry.won == false)
        #expect(!entry.canResume)
    }

    @Test("Les changements sont regroupés avant d'être gardés")
    func changesAreGathered() async throws {
        let (session, sent) = session()
        session.autosaveDelay = .milliseconds(20)
        session.handle(try state(moveNumber: 1))
        session.handle(try state(moveNumber: 2))
        session.handle(try state(moveNumber: 3))
        #expect(sent.names.isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        #expect(sent.names == ["export_sgf"])
    }

    @Test("Quitter attend que la partie soit écrite")
    func quittingWaits() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 3))
        var quit = false
        session.prepareToQuit { quit = true }
        #expect(!quit)
        try answerAutosave(session, sent, "(;GM[1]SZ[9];B[ee])")
        #expect(quit)
    }

    @Test("Sans rien à écrire, quitter n'attend pas")
    func quittingWithNothingToWrite() {
        let (session, _) = session()
        var quit = false
        session.prepareToQuit { quit = true }
        #expect(quit)
    }

    // -- the cards -------------------------------------------------------------------

    private func kept(
        _ library: GameLibrary, kind: LibraryEntry.Kind = .ai, status: LibraryEntry.Status = .inProgress,
        hash: String? = nil
    ) throws -> LibraryEntry {
        let entry = LibraryEntry(
            kind: kind, createdAt: .now, updatedAt: .now, size: 9, komi: 6.5,
            humanColor: kind == .ai ? .white : nil, aiStrategy: kind == .ai ? "ai:human" : nil,
            aiSettingValue: kind == .ai ? 5 : nil, moveCount: 3, status: status,
            analysis: .none, finalBoard: .empty(size: 9), sourceHash: hash
        )
        try library.save(entry, contents: "(;GM[1]SZ[9];B[ee];W[cc];B[gg])")
        return entry
    }

    @Test("Reprendre une partie contre KataGo la confie au pont, couleur et mode compris")
    func resumes() throws {
        let library = GameLibrary(directory: nil)
        let entry = try kept(library)
        let (session, sent) = session(library: library)
        session.open(entry)
        let command = try #require(sent.commands.last)
        #expect(command.cmd == "continue_game")
        #expect(command.humanColor == .white)
        #expect(command.aiStrategy == "ai:human")
        #expect(command.aiSettings?.values.first == 5)
        #expect(command.contents == "(;GM[1]SZ[9];B[ee];W[cc];B[gg])")
        #expect(session.currentEntryID == entry.id)
        #expect(!session.isShowingLibrary)
    }

    @Test("Revoir une partie terminée l'ouvre comme un enregistrement, sous la même entrée")
    func reviews() throws {
        let library = GameLibrary(directory: nil)
        let entry = try kept(library, status: .finished)
        let (session, sent) = session(library: library)
        session.open(entry)
        #expect(sent.names == ["load_sgf"])
        #expect(session.currentEntryID == entry.id)
    }

    @Test("Une partie Kifu ne se reprend pas : elle se revoit")
    func kifuIsReviewed() throws {
        let library = GameLibrary(directory: nil)
        let entry = try kept(library, kind: .kifu)
        #expect(!entry.canResume)
        let (session, sent) = session(library: library)
        session.open(entry)
        #expect(sent.names == ["load_sgf"])
    }

    @Test("Le même fichier rouvert retrouve son entrée et le SGF de la bibliothèque")
    func sameFileSameEntry() throws {
        let library = GameLibrary(directory: nil)
        let entry = try kept(library, kind: .record, status: .finished, hash: GameLibrary.fingerprint(record.contents))
        let (session, sent) = session(library: library)
        session.requestOpening(record)
        #expect(session.currentEntryID == entry.id)
        #expect(sent.commands.last?.contents == "(;GM[1]SZ[9];B[ee];W[cc];B[gg])")
    }

    @Test("Un fichier nouveau devient une nouvelle entrée, avec son empreinte")
    func newFileNewEntry() throws {
        let (session, sent) = session()
        session.requestOpening(record)
        session.handle(try BridgeEvent.decode(line: """
            {"event":"state","id":2,"size":9,"stones":[],"to_play":"B","move_number":2,"move_count":2,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],"score_lead":null,\
            "human_color":"B","status":"review","result":null,"view":"analysis"}
            """))
        session.flushAutosave()
        try answerAutosave(session, sent, record.contents)
        let entry = try #require(session.library.entries.first)
        #expect(entry.kind == .record)
        #expect(entry.sourceHash == GameLibrary.fingerprint(record.contents))
        #expect(entry.humanColor == nil)
    }

    @Test("La partie qui vit dans le moteur ne se supprime pas ; les autres si")
    func deleting() throws {
        let library = GameLibrary(directory: nil)
        let other = try kept(library, status: .finished)
        let (session, sent) = session(library: library)
        session.handle(try state(moveNumber: 3))
        session.flushAutosave()
        try answerAutosave(session, sent, "(;GM[1]SZ[9];B[ee])")
        let id = try #require(session.currentEntryID)
        let live = try #require(session.library.entry(id))
        #expect(!session.canDelete(live))
        session.delete(live)
        #expect(session.library.entry(live.id) != nil)
        #expect(session.canDelete(other))
        session.delete(other)
        #expect(session.library.entry(other.id) == nil)
        #expect(session.library.contents(of: other.id) == nil)
    }

    @Test("Exporter une carte passe par le panneau, avec le texte gardé")
    func exportingACard() throws {
        let library = GameLibrary(directory: nil)
        let entry = try kept(library, kind: .record, status: .finished)
        let (session, _) = session(library: library)
        session.export(entry)
        #expect(session.pendingExport?.contents == "(;GM[1]SZ[9];B[ee];W[cc];B[gg])")
    }

    @Test("Au démarrage du moteur, la bibliothèque reste à l'écran")
    func libraryAtLaunch() {
        let (session, _) = session()
        #expect(session.isShowingLibrary)
        session.newGame()
        #expect(!session.isShowingLibrary)
    }

    @Test("Revenir à la bibliothèque n'interrompt pas la partie")
    func backToTheLibrary() throws {
        let (session, sent) = session()
        session.handle(try state(moveNumber: 3))
        session.showLibrary()
        #expect(session.isShowingLibrary)
        #expect(sent.names == ["export_sgf"])
        #expect(session.state != nil)
    }
}

@MainActor
@Suite("Bibliothèque sur disque")
struct GameLibraryDiskTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "moyo-library-\(UUID().uuidString)")
    }

    private func entry() -> LibraryEntry {
        LibraryEntry(
            kind: .record, createdAt: .now, updatedAt: .now, size: 19, komi: 6.5, blackName: "Shin Jinseo",
            whiteName: "Ke Jie", result: "B+1.5", moveCount: 287, status: .finished,
            analysis: .partial(done: 100, total: 288), finalBoard: .empty(size: 19), title: "Finale LG Cup"
        )
    }

    @Test("Une partie écrite se relit, index et SGF")
    func roundTrip() throws {
        let url = directory()
        defer { try? FileManager.default.removeItem(at: url) }
        let entry = entry()
        try GameLibrary(directory: url).save(entry, contents: "(;GM[1])")
        let reread = GameLibrary(directory: url)
        #expect(reread.entries.map(\.id) == [entry.id])
        #expect(reread.entries.first?.analysis == .partial(done: 100, total: 288))
        #expect(reread.contents(of: entry.id) == "(;GM[1])")
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "Games/\(entry.id.uuidString).sgf").path))
    }

    @Test("Un index illisible repart de zéro, les SGF restent")
    func corruptIndex() throws {
        let url = directory()
        defer { try? FileManager.default.removeItem(at: url) }
        let entry = entry()
        try GameLibrary(directory: url).save(entry, contents: "(;GM[1])")
        try Data("pas du json".utf8).write(to: url.appending(path: "library.json"))
        let reread = GameLibrary(directory: url)
        #expect(reread.entries.isEmpty)
        #expect(reread.contents(of: entry.id) == "(;GM[1])")
    }

    @Test("Supprimer retire l'entrée et son SGF")
    func deletes() throws {
        let url = directory()
        defer { try? FileManager.default.removeItem(at: url) }
        let library = GameLibrary(directory: url)
        let entry = entry()
        try library.save(entry, contents: "(;GM[1])")
        try library.delete(entry.id)
        #expect(GameLibrary(directory: url).entries.isEmpty)
        #expect(library.contents(of: entry.id) == nil)
    }

    @Test("MOYO_LIBRARY déplace la bibliothèque")
    func environment() {
        let library = GameLibrary.onDisk(environment: ["MOYO_LIBRARY": "/tmp/ailleurs"])
        #expect(library.directory?.path == "/tmp/ailleurs")
    }
}

@Suite("Ce que dit une carte")
struct LibraryEntryTests {
    private func entry(
        kind: LibraryEntry.Kind, black: String? = nil, white: String? = nil, title: String? = nil,
        human: PlayerColor? = nil, result: String? = nil
    ) -> LibraryEntry {
        LibraryEntry(
            kind: kind, createdAt: .now, updatedAt: .now, size: 19, komi: 6.5, blackName: black,
            whiteName: white, humanColor: human, aiStrategy: kind == .ai ? "ai:human" : nil, result: result,
            moveCount: 10, status: .finished, analysis: .complete, finalBoard: .empty(size: 19), title: title
        )
    }

    @Test("Les titres : contre KataGo, les deux joueurs, ou le nom de la partie")
    func titles() {
        #expect(entry(kind: .ai, black: "Thibaut", white: "KataGo").displayTitle == "Contre KataGo")
        #expect(entry(kind: .kifu, black: "Thibaut", white: "Léo").displayTitle == "Thibaut – Léo")
        #expect(entry(kind: .record).displayTitle == "Noir – Blanc")
        #expect(entry(kind: .record, black: "Lee", white: "AlphaGo", title: "Partie 4").displayTitle == "Partie 4")
    }

    @Test("Gagnée ou perdue, seulement quand le joueur avait une couleur")
    func outcome() {
        #expect(entry(kind: .ai, human: .white, result: "W+3.5").won == true)
        #expect(entry(kind: .ai, human: .black, result: "W+R").won == false)
        #expect(entry(kind: .record, result: "B+R").won == nil)
        #expect(entry(kind: .ai, human: .black, result: "W+3.5").displayResult == "W+3,5")
    }

    @Test("L'analyse comptée par le pont")
    func analysis() {
        #expect(LibraryEntry.Analysis(done: 0, total: 10) == .none)
        #expect(LibraryEntry.Analysis(done: 6, total: 10) == .partial(done: 6, total: 10))
        #expect(LibraryEntry.Analysis(done: 10, total: 10) == .complete)
    }
}
