import Foundation
import Testing

@testable import MoyoCore

@Suite("Lecture du plateau envoyé par le téléphone")
struct PhoneBoardTests {
    @Test("Une ligne JSON devient des pierres, ligne 0 en haut")
    func decodesStones() throws {
        let line = """
            {"size":3,"rows":["X..","...","..O"],"status":"locked"}
            """
        let board = try #require(PhoneBoard(line: line))
        #expect(board.size == 3)
        #expect(board.status == "locked")
        #expect(board.stones == [Stone(row: 0, col: 0, color: .black), Stone(row: 2, col: 2, color: .white)])
    }

    @Test("La première ligne apporte l'historique de la partie")
    func decodesHistory() throws {
        let line = """
            {"history":{"moves":[{"color":"B","point":[0,0]},{"color":"W"},\
            {"color":"B","point":[1,1],"erased":[[2,2]]}],"setup":{"B":[[0,2]],"W":[]}},\
            "rows":["X.X",".X.","..."],"size":3,"status":"locked"}
            """
        let history = try #require(PhoneBoard(line: line)?.history)
        #expect(history.setupBlack == [[0, 2]])
        #expect(history.setupWhite == [])
        #expect(history.moves == [
            PhoneMove(color: "B", point: [0, 0]),
            PhoneMove(color: "W"),
            PhoneMove(color: "B", point: [1, 1], erased: [[2, 2]]),
        ])
        #expect(PhoneBoard(line: "{\"size\":2,\"rows\":[\"X.\",\"..\"]}")?.history == nil)
    }

    @Test("L'historique part au pont sous ses propres noms")
    func encodesHistoryForTheBridge() throws {
        let history = PhoneHistory(setupBlack: [[0, 2]], setupWhite: [], moves: [PhoneMove(color: "W")])
        let line = try BridgeCommand.followBoard(id: 3, rows: ["..."], history: history).encodedLine()
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        let sent = try #require(object["history"] as? [String: Any])
        #expect(sent["setup_black"] as? [[Int]] == [[0, 2]])
        #expect((sent["moves"] as? [[String: Any]])?.first?["color"] as? String == "W")
        let plain = try BridgeCommand.followBoard(id: 4, rows: ["..."]).encodedLine()
        #expect(try #require(try JSONSerialization.jsonObject(with: plain) as? [String: Any])["history"] == nil)
    }

    @Test("Un plateau incohérent est ignoré")
    func rejectsMalformed() {
        #expect(PhoneBoard(line: "{\"size\":3,\"rows\":[\"X..\",\"...\"]}") == nil)
        #expect(PhoneBoard(line: "pas du json") == nil)
        #expect(PhoneBoard(line: "{\"size\":2,\"rows\":[\"X..\",\"...\"]}") == nil)
    }

    @Test("Les lignes partielles attendent leur fin")
    @MainActor
    func splitsOnNewlines() {
        let link = PhoneLink()
        var received: [PhoneBoard] = []
        link.onBoard = { received.append($0) }
        let full = "{\"size\":2,\"rows\":[\"X.\",\"..\"]}\n"
        let half = "{\"size\":2,\"rows\":[\"XO\","
        link.consume(Data((full + half).utf8))
        #expect(received.count == 1)
        link.consume(Data("\"..\"]}\n".utf8))
        #expect(received.count == 2)
        #expect(received[1].stones.count == 2)
    }
}
