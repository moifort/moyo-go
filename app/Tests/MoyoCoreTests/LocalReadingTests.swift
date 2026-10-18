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
