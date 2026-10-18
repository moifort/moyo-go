import CoreGraphics
import Foundation
import Testing

@testable import MoyoCore

@Suite("La zone du combat tracée à la main")
struct DrawnZoneTests {
    @Test("Un glisser donne le même rectangle dans un sens ou dans l'autre")
    func spanningIsOrdered() {
        let zone = LocalZone(top: 2, left: 3, bottom: 8, right: 10)
        #expect(LocalZone(spanning: Point(row: 2, col: 3), Point(row: 8, col: 10)) == zone)
        #expect(LocalZone(spanning: Point(row: 8, col: 10), Point(row: 2, col: 3)) == zone)
        #expect(LocalZone(spanning: Point(row: 8, col: 3), Point(row: 2, col: 10)) == zone)
    }

    @Test("Un glisser qui sort du goban s'arrête sur son bord")
    func nearestIntersectionIsClamped() {
        let geometry = BoardGeometry(size: 9, side: 400)
        #expect(geometry.nearestIntersection(to: CGPoint(x: -50, y: -50)) == Point(row: 0, col: 0))
        #expect(geometry.nearestIntersection(to: CGPoint(x: 900, y: 10)) == Point(row: 0, col: 8))
        let inside = geometry.position(row: 4, col: 6)
        #expect(geometry.nearestIntersection(to: CGPoint(x: inside.x + 5, y: inside.y - 5)) == Point(row: 4, col: 6))
    }

    @Test("La commande porte la zone tracée, ou rien pour revenir à la zone automatique")
    func commandEncoding() throws {
        let zone = LocalZone(top: 1, left: 2, bottom: 7, right: 9)
        let drawn = try BridgeCommand.setLocalZone(id: 4, zone: zone).encodedLine()
        let object = try #require(try JSONSerialization.jsonObject(with: drawn) as? [String: Any])
        #expect(object["cmd"] as? String == "set_local_zone")
        let sent = try #require(object["zone"] as? [String: Int])
        #expect(sent == ["top": 1, "left": 2, "bottom": 7, "right": 9])

        let cleared = try BridgeCommand.setLocalZone(id: 5, zone: nil).encodedLine()
        let plain = try #require(try JSONSerialization.jsonObject(with: cleared) as? [String: Any])
        #expect(plain["cmd"] as? String == "set_local_zone")
        #expect(plain["zone"] == nil)
    }

    @Test("L'état dit si la zone vient du joueur")
    func drawnFlagDecodes() throws {
        let line = """
            {"event":"state","id":3,"size":9,"stones":[],"to_play":"B","move_number":0,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[null],\
            "score_lead":null,"human_color":"B","status":"review","result":null,\
            "move_count":5,"variation_depth":0,"best_move":null,"local_move":null,\
            "local_zone":{"top":5,"left":0,"bottom":8,"right":3},"local_zone_drawn":true}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            return
        }
        #expect(state.localZoneDrawn == true)
        #expect(state.localZone == LocalZone(top: 5, left: 0, bottom: 8, right: 3))
    }
}
