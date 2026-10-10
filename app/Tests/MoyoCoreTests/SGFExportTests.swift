import Foundation
import Testing

@testable import MoyoCore

@Suite("Enregistrement d'une partie en SGF")
struct SGFExportTests {
    private static let paris = TimeZone(identifier: "Europe/Paris")!

    /// 10 octobre 2026, 15 h 04 à Paris.
    private static let afternoon = Date(timeIntervalSince1970: 1_791_637_440)

    @Test("Une partie jouée est nommée d'après le moment où on l'enregistre")
    func gameName() {
        let name = SGFExport.suggestedName(recordName: nil, date: Self.afternoon, timeZone: Self.paris)
        #expect(name == "Moyo 2026-10-10 15h04.sgf")
    }

    @Test("Un enregistrement relu garde son nom")
    func recordName() {
        #expect(SGFExport.suggestedName(recordName: "Shusaku.sgf", date: Self.afternoon) == "Shusaku.sgf")
    }

    @Test("Un nom sans extension la reçoit")
    func missingExtension() {
        #expect(SGFExport.suggestedName(recordName: "partie", date: Self.afternoon) == "partie.sgf")
    }

    @Test("L'IA porte son mode et son réglage")
    func aiWithSetting() {
        let mode = AIMode.mode(for: "ai:human")
        #expect(SGFExport.aiName(mode: mode, value: 5) == "KataGo · Modèle humain, 5 kyu")
    }

    @Test("Un mode sans réglage n'a que son nom")
    func aiWithoutSetting() {
        let mode = AIMode.mode(for: "ai:default")
        #expect(SGFExport.aiName(mode: mode, value: nil) == "KataGo · Pleine force")
    }

    @Test("Chacun prend la couleur qu'il a jouée")
    func colours() {
        let asBlack = SGFExport.players(humanColor: .black, human: "Moi", ai: "KataGo")
        #expect(asBlack.black == "Moi")
        #expect(asBlack.white == "KataGo")

        let asWhite = SGFExport.players(humanColor: .white, human: "Moi", ai: "KataGo")
        #expect(asWhite.black == "KataGo")
        #expect(asWhite.white == "Moi")
    }

    @Test("Un joueur sans nom n'en porte aucun")
    func anonymousHuman() {
        let players = SGFExport.players(humanColor: .black, human: "  ", ai: "KataGo")
        #expect(players.black == nil)
    }

    @Test("Le fichier est écrit en UTF-8, et remplacé s'il existe")
    func write() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("partie.sgf")

        try SGFExport.write("(;GM[1]FF[4]SZ[9];B[ee])", to: url)
        try SGFExport.write("(;GM[1]FF[4]CA[UTF-8]SZ[9]PB[本因坊秀策];B[ee])", to: url)

        let data = try Data(contentsOf: url)
        #expect(String(data: data, encoding: .utf8) == "(;GM[1]FF[4]CA[UTF-8]SZ[9]PB[本因坊秀策];B[ee])")
        // Ce que l'app écrit, elle doit pouvoir le relire.
        #expect(try SGFImport.read(url).contents.contains("本因坊秀策"))
    }

    @Test("Un dossier introuvable est dit, pas avalé")
    func notWritable() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/partie.sgf")
        #expect(throws: SGFExport.Failure.notWritable("partie.sgf")) {
            try SGFExport.write("(;)", to: url)
        }
    }

    @Test("La commande porte le nom des deux joueurs")
    func command() throws {
        let line = try BridgeCommand.exportSGF(id: 3, blackName: "Moi", whiteName: nil).encodedLine()
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(object["cmd"] as? String == "export_sgf")
        #expect(object["black_name"] as? String == "Moi")
        #expect(object["white_name"] == nil)
    }

    @Test("Le pont répond par le texte de la partie")
    func event() throws {
        let line = #"{"event":"sgf","id":3,"contents":"(;GM[1]FF[4]SZ[9];B[ee])"}"#
        guard case .sgf(let id, let contents) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement sgf")
            return
        }
        #expect(id == 3)
        #expect(contents == "(;GM[1]FF[4]SZ[9];B[ee])")
    }
}
