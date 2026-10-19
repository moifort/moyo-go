import Foundation
import Testing

@testable import MoyoCore

@Suite("La lecture du combat local")
struct LocalReadingTests {
    @Test("Un état de revue porte la zone, le coup local et la séquence en cours")
    func localFieldsDecode() throws {
        let line = """
            {"event":"state","id":3,"size":19,"stones":[],"to_play":"W","move_number":40,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[null],\
            "score_lead":null,"human_color":"B","status":"review","result":null,\
            "move_count":211,"variation_depth":1,"variation_kind":"local","best_move":null,\
            "local_move":{"row":4,"col":15,"points_lost":null},\
            "local_zone":{"top":1,"left":12,"bottom":7,"right":18}}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(state.variationKind == .local)
        #expect(state.localMove == LocalMove(row: 4, col: 15, pointsLost: nil))
        #expect(state.localZone == LocalZone(top: 1, left: 12, bottom: 7, right: 18))
    }

    @Test("Un pont plus ancien, sans lecture locale, se décode encore")
    func absentFieldsAreNil() throws {
        let line = """
            {"event":"state","id":3,"size":9,"stones":[],"to_play":"B","move_number":0,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[null],\
            "score_lead":null,"human_color":"B","status":"review","result":null,\
            "move_count":5,"variation_depth":0,"best_move":null}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(state.localMove == nil)
        #expect(state.localZone == nil)
        #expect(state.variationKind == nil)
    }

    @Test("Le coût du coup local se dit en français")
    func costLabel() {
        #expect(LocalMove(row: 0, col: 0, pointsLost: nil).costLabel == nil)
        #expect(LocalMove(row: 0, col: 0, pointsLost: 0.04).costLabel == "aussi bon que le meilleur coup")
        #expect(LocalMove(row: 0, col: 0, pointsLost: 1.5).costLabel == "coûte 1,5 point")
        #expect(LocalMove(row: 0, col: 0, pointsLost: 3.24).costLabel == "coûte 3,2 points")
    }

    @Test("La commande de variante dit quelle ligne suivre")
    func variationKindIsSent() throws {
        let local = try BridgeCommand.variation(id: 9, step: 1, kind: .local).encodedLine()
        let object = try #require(try JSONSerialization.jsonObject(with: local) as? [String: Any])
        #expect(object["cmd"] as? String == "variation")
        #expect(object["step"] as? Int == 1)
        #expect(object["kind"] as? String == "local")

        let best = try BridgeCommand.variation(id: 10, step: -1).encodedLine()
        let plain = try #require(try JSONSerialization.jsonObject(with: best) as? [String: Any])
        #expect(plain["kind"] as? String == "best")
    }
}

@Suite("Le libellé d'une pastille, au survol")
struct ProposalCaptionTests {
    private func state(variation: String = #"0,"variation_kind":null"#, best: String, local: String) throws -> GameState {
        let line = """
            {"event":"state","id":1,"size":19,"stones":[],"to_play":"B","move_number":3,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[null],\
            "score_lead":null,"human_color":"B","status":"review","result":null,\
            "move_count":9,"variation_depth":\(variation),"best_move":\(best),"local_move":\(local),\
            "local_zone":{"top":0,"left":0,"bottom":6,"right":6}}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return state
    }

    @Test("Chaque pastille dit ce qu'elle est, et rien ailleurs")
    func eachDiscSaysWhatItIs() throws {
        let s = try state(
            best: #"{"row":10,"col":10,"points_lost":0}"#,
            local: #"{"row":3,"col":3,"points_lost":2.5}"#
        )
        #expect(s.proposalCaption(at: Point(row: 10, col: 10)) == "Meilleur coup selon KataGo")
        #expect(s.proposalCaption(at: Point(row: 3, col: 3)) == "Meilleur coup local, coûte 2,5 points")
        #expect(s.proposalCaption(at: Point(row: 0, col: 0)) == nil)
    }

    @Test("Une seule pastille quand le meilleur coup est déjà local")
    func sharedDisc() throws {
        let s = try state(
            best: #"{"row":3,"col":3,"points_lost":0}"#,
            local: #"{"row":3,"col":3,"points_lost":0}"#
        )
        #expect(s.proposalCaption(at: Point(row: 3, col: 3)) == "Meilleur coup selon KataGo, et meilleur coup local")
    }

    @Test("Pendant le déroulé, la pastille annonce le coup suivant")
    func duringAWalk() throws {
        let s = try state(
            variation: #"2,"variation_kind":"local""#,
            best: "null",
            local: #"{"row":4,"col":4,"points_lost":null}"#
        )
        #expect(s.proposalCaption(at: Point(row: 4, col: 4)) == "Coup suivant de la séquence locale")
    }
}

@Suite("L'attente de la lecture locale")
struct LocalPendingTests {
    @Test("Le pont dit quand la lecture locale est encore en cours")
    func pendingDecodes() throws {
        let line = """
            {"event":"state","id":1,"size":19,"stones":[],"to_play":"B","move_number":3,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[null],\
            "score_lead":null,"human_color":"B","status":"review","result":null,\
            "move_count":9,"variation_depth":0,"best_move":null,"local_move":null,\
            "local_zone":{"top":0,"left":0,"bottom":6,"right":6},"local_pending":true}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(state.isReadingLocally)
    }
}

@Suite("La lecture locale masquée")
struct HiddenLocalTests {
    @Test("Masquée, la pastille bleue n'a pas de libellé")
    func hiddenLocalHasNoCaption() throws {
        let line = """
            {"event":"state","id":1,"size":19,"stones":[],"to_play":"B","move_number":3,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[null],\
            "score_lead":null,"human_color":"B","status":"review","result":null,\
            "move_count":9,"variation_depth":0,"best_move":{"row":3,"col":3,"points_lost":0},\
            "local_move":{"row":5,"col":5,"points_lost":1.5},\
            "local_zone":{"top":0,"left":0,"bottom":6,"right":6},"local_wanted":false}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(state.proposalCaption(at: Point(row: 5, col: 5), showingLocal: false) == nil)
        #expect(state.proposalCaption(at: Point(row: 3, col: 3), showingLocal: false) == "Meilleur coup selon KataGo")
        #expect(state.proposalCaption(at: Point(row: 5, col: 5)) == "Meilleur coup local, coûte 1,5 point")
    }
}
