import Foundation
import Testing

@testable import MoyoCore

@Suite("Décodage des événements du pont")
struct BridgeEventTests {
    @Test("Un état complet")
    func stateEvent() throws {
        let line = """
            {"event":"state","id":2,"size":9,"stones":[{"row":0,"col":1,"color":"B"}],\
            "to_play":"W","move_number":1,"last_move":{"row":0,"col":1},\
            "captures":{"by_black":1,"by_white":0},"score_history":[null,1.5],\
            "score_lead":1.5,"human_color":"B","status":"playing","result":null}
            """
        guard case .state(let id, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(id == 2)
        #expect(state.size == 9)
        #expect(state.stones == [Stone(row: 0, col: 1, color: .black)])
        #expect(state.toPlay == .white)
        #expect(state.moveNumber == 1)
        #expect(state.lastMove == Point(row: 0, col: 1))
        #expect(state.captures == Captures(byBlack: 1, byWhite: 0))
        #expect(state.scoreHistory == [nil, 1.5])
        #expect(state.humanColor == .black)
        #expect(state.status == .playing)
        #expect(state.result == nil)
    }

    @Test("Un état d'événement spontané n'a pas d'identifiant")
    func spontaneousState() throws {
        let line = """
            {"event":"state","id":null,"size":9,"stones":[],"to_play":"B","move_number":0,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"playing","result":null}
            """
        guard case .state(let id, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(id == nil)
        #expect(state.lastMove == nil)
        #expect(state.scoreLead == nil)
    }

    @Test("Une partie terminée porte son résultat")
    func finishedGame() throws {
        let line = """
            {"event":"state","id":null,"size":9,"stones":[],"to_play":"W","move_number":4,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"finished","result":"B+R"}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(state.status == .finished)
        #expect(state.result == "B+R")
        #expect(!state.isHumanTurn)
    }

    @Test("Le trait du joueur humain")
    func humanTurn() throws {
        let line = """
            {"event":"state","id":null,"size":9,"stones":[],"to_play":"B","move_number":0,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"playing","result":null}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(state.isHumanTurn)
    }

    @Test("Les événements simples")
    func simpleEvents() throws {
        guard case .thinking(let value) = try BridgeEvent.decode(line: #"{"event":"thinking","id":null,"value":true}"#)
        else {
            Issue.record("attendu thinking")
            return
        }
        #expect(value)

        guard
            case .score(let move, let lead) = try BridgeEvent.decode(
                line: #"{"event":"score","id":null,"move_number":7,"score_lead":-2.5}"#)
        else {
            Issue.record("attendu score")
            return
        }
        #expect(move == 7)
        #expect(lead == -2.5)

        guard
            case .failure(let id, let code, _) = try BridgeEvent.decode(
                line: #"{"event":"error","id":3,"code":"illegal_move","message":"Space occupied"}"#)
        else {
            Issue.record("attendu error")
            return
        }
        #expect(id == 3)
        #expect(code == "illegal_move")

        guard
            case .engineFailed(let message) = try BridgeEvent.decode(
                line: #"{"event":"engine_failed","id":null,"message":"introuvable"}"#)
        else {
            Issue.record("attendu engine_failed")
            return
        }
        #expect(message == "introuvable")
    }

    @Test("Un événement inconnu est ignoré au lieu de tout casser")
    func unknownEvent() throws {
        guard case .unknown(let name) = try BridgeEvent.decode(line: #"{"event":"ponder","id":null,"depth":12}"#) else {
            Issue.record("attendu unknown")
            return
        }
        #expect(name == "ponder")
    }

    @Test("Les commandes sortent en snake_case, sur une seule ligne")
    func commandEncoding() throws {
        let line = try BridgeCommand.newGame(
            id: 1, size: 19, komi: 6.5, rules: "japanese",
            humanColor: .black, aiStrategy: "ai:human", aiSettings: ["human_kyu_rank": 8]
        ).encodedLine()
        let text = String(decoding: line, as: UTF8.self)
        #expect(text.hasSuffix("\n"))
        #expect(text.dropLast().contains("\n") == false)

        let object = try #require(
            try JSONSerialization.jsonObject(with: line) as? [String: Any]
        )
        #expect(object["cmd"] as? String == "new_game")
        #expect(object["human_color"] as? String == "B")
        #expect(object["ai_strategy"] as? String == "ai:human")
        #expect(object["row"] == nil)
    }

    @Test("Une commande de coup ne porte que ses coordonnées")
    func playEncoding() throws {
        let line = try BridgeCommand.play(id: 4, row: 3, col: 15).encodedLine()
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(object["cmd"] as? String == "play")
        #expect(object["row"] as? Int == 3)
        #expect(object["col"] as? Int == 15)
        #expect(object["size"] == nil)
    }

    @Test("Un état de revue porte le record, son meilleur coup et sa longueur")
    func reviewState() throws {
        let line = """
            {"event":"state","id":7,"size":19,"stones":[],"to_play":"B","move_number":4,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[null],\
            "score_lead":null,"human_color":"B","status":"review","result":"B+2",\
            "move_count":211,"variation_depth":2,"best_move":{"row":15,"col":3,"points_lost":4.25},\
            "game_info":{"black_name":"Shusaku","white_name":null,"black_rank":"4d",\
            "white_rank":null,"result":"B+2","date":null,"event":"Ear-reddening"}}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(state.status == .review)
        #expect(state.isReviewing)
        #expect(state.moveCount == 211)
        #expect(state.variationDepth == 2)
        #expect(state.bestMove == BestMove(row: 15, col: 3, pointsLost: 4.25))
        #expect(state.gameInfo?.label(for: .black) == "Shusaku 4d")
        #expect(state.gameInfo?.label(for: .white) == nil)
        #expect(state.gameInfo?.event == "Ear-reddening")
        // Un record se lit en analyse : un clic y pose une pierre, des deux couleurs.
        #expect(state.isAnalysing)
        #expect(state.acceptsClicks)
        #expect(!state.isHumanTurn)
        #expect(!state.hasLiveGame)
    }

    @Test("Une partie en cours ne porte aucun champ de revue")
    func playingStateHasNoReviewFields() throws {
        let line = """
            {"event":"state","id":1,"size":9,"stones":[],"to_play":"B","move_number":0,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[],\
            "score_lead":null,"human_color":"B","status":"playing","result":null}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(!state.isReviewing)
        #expect(state.moveCount == nil)
        #expect(state.bestMove == nil)
        #expect(state.gameInfo == nil)
        #expect(state.variationDepth == nil)
    }

    @Test("La progression de l'analyse")
    func analysisProgress() throws {
        let line = #"{"event":"analysis_progress","id":null,"done":34,"total":211}"#
        guard case .analysisProgress(let done, let total) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement analysis_progress")
            return
        }
        #expect(done == 34)
        #expect(total == 211)
    }
}
