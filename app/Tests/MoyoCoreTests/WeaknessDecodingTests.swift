import Testing
@testable import MoyoCore

@Suite("Les faiblesses des groupes")
struct WeaknessDecodingTests {
    private func state(_ fields: String) throws -> GameState {
        let line = """
            {"event":"state","id":1,"size":9,"stones":[],"to_play":"B","move_number":3,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[null],\
            "score_lead":null,"human_color":"B","status":"review","result":null,\
            "move_count":9,"variation_depth":0,"best_move":null,"local_move":null\(fields)}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement state")
            throw CancellationError()
        }
        return state
    }

    @Test("Les points arrivent avec la couleur de qui frapperait")
    func decodes() throws {
        let s = try state(#","weaknessing":true,"weaknesses_pending":false,"weaknesses":[{"row":5,"col":4,"color":"B","swing":2.8}]"#)
        #expect(s.weaknessing == true)
        #expect(s.weaknesses == [WeakPoint(row: 5, col: 4, color: .black, swing: 2.8)])
        #expect(s.weakMarks.map(\.colors) == [[.black]])
    }

    @Test("Un pont plus ancien n'en dit rien")
    func olderBridge() throws {
        let s = try state("")
        #expect(s.weaknessing == nil)
        #expect(s.weakMarks.isEmpty)
    }

    @Test("Le point vital commun aux deux couleurs n'est dessiné qu'une fois")
    func sharedVitalPoint() throws {
        let s = try state(#","weaknesses":[{"row":2,"col":2,"color":"W","swing":3},{"row":5,"col":4,"color":"B","swing":2.5},{"row":2,"col":2,"color":"B","swing":2.1}]"#)
        let marks = s.weakMarks
        #expect(marks.map(\.point) == [Point(row: 2, col: 2), Point(row: 5, col: 4)])
        #expect(marks[0].colors == [.black, .white])
    }
}
