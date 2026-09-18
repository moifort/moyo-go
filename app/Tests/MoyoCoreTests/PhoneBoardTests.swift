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
