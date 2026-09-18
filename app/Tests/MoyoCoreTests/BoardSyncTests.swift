import Foundation
import Testing

@testable import MoyoCore

@Suite("Le coup déduit du plateau réel")
struct BoardSyncTests {
    private func game(stones: [Stone], toPlay: PlayerColor = .black, humanColor: PlayerColor = .black,
                      status: String = "playing", size: Int = 9) throws -> GameState {
        let stoneJSON = stones.map { "{\"row\":\($0.row),\"col\":\($0.col),\"color\":\"\($0.color.rawValue)\"}" }
            .joined(separator: ",")
        let line = """
            {"size":\(size),"stones":[\(stoneJSON)],"to_play":"\(toPlay.rawValue)","move_number":\(stones.count),\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],"score_lead":null,\
            "human_color":"\(humanColor.rawValue)","status":"\(status)","result":null}
            """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GameState.self, from: Data(line.utf8))
    }

    @Test("Une pierre noire nouvelle au tour de noir est le coup")
    func singleNewStoneIsTheMove() throws {
        let known = [Stone(row: 4, col: 4, color: .black), Stone(row: 2, col: 2, color: .white)]
        let phone = PhoneBoard(size: 9, stones: known + [Stone(row: 6, col: 3, color: .black)])
        #expect(BoardSync.pendingMove(phone: phone, game: try game(stones: known)) == Point(row: 6, col: 3))
    }

    @Test("Rien à jouer quand le plateau et la partie coïncident")
    func identicalBoardsGiveNothing() throws {
        let known = [Stone(row: 4, col: 4, color: .black)]
        #expect(BoardSync.pendingMove(phone: PhoneBoard(size: 9, stones: known), game: try game(stones: known)) == nil)
    }

    @Test("Deux pierres nouvelles ne font pas un coup")
    func twoNewStonesAreIgnored() throws {
        let phone = PhoneBoard(size: 9, stones: [Stone(row: 1, col: 1, color: .black), Stone(row: 2, col: 2, color: .black)])
        #expect(BoardSync.pendingMove(phone: phone, game: try game(stones: [])) == nil)
    }

    @Test("Une pierre de la mauvaise couleur est ignorée")
    func wrongColourIsIgnored() throws {
        let phone = PhoneBoard(size: 9, stones: [Stone(row: 1, col: 1, color: .white)])
        #expect(BoardSync.pendingMove(phone: phone, game: try game(stones: [])) == nil)
    }

    @Test("Pas de coup pendant le tour de l'IA")
    func nothingDuringAITurn() throws {
        let phone = PhoneBoard(size: 9, stones: [Stone(row: 1, col: 1, color: .white)])
        #expect(BoardSync.pendingMove(phone: phone, game: try game(stones: [], toPlay: .white)) == nil)
    }

    @Test("Une pierre manquante sur le plateau réel ne joue rien")
    func missingStoneIsNotAMove() throws {
        let known = [Stone(row: 4, col: 4, color: .black), Stone(row: 2, col: 2, color: .white)]
        let phone = PhoneBoard(size: 9, stones: [known[1], Stone(row: 0, col: 0, color: .black)])
        #expect(BoardSync.pendingMove(phone: phone, game: try game(stones: known)) == nil)
    }

    @Test("Une taille différente ne joue rien")
    func sizeMismatchGivesNothing() throws {
        let phone = PhoneBoard(size: 9, stones: [Stone(row: 1, col: 1, color: .black)])
        #expect(BoardSync.pendingMove(phone: phone, game: try game(stones: [], size: 19)) == nil)
    }
}
