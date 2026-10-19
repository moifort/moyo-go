import Testing

@testable import MoyoCore

@Suite("Décodage de l'estimation du score")
struct EstimateDecodingTests {
    static func line(estimating: Bool?, estimate: String?) -> String {
        var fields = """
            {"event":"state","id":3,"size":9,"stones":[{"row":4,"col":4,"color":"W"}],\
            "to_play":"B","move_number":7,"last_move":null,\
            "captures":{"by_black":0,"by_white":0},"score_history":[],"score_lead":1.5,\
            "human_color":"B","status":"playing","result":null
            """
        if let estimating { fields += ",\"estimating\":\(estimating)" }
        if let estimate { fields += ",\"estimate\":\(estimate)" }
        return fields + "}"
    }

    static let settled = """
        {"lead":5.5,"points":[{"row":0,"col":0,"color":"B"}],"dead_stones":[{"row":4,"col":4}],\
        "count":{"black":12.0,"white":6.5,"komi":6.5,"territory":{"B":11,"W":0},\
        "prisoners":{"B":1,"W":0},"stones":null,"result":"B+5.5",\
        "points":[{"row":0,"col":0,"color":"B"}],"dead_stones":[{"row":4,"col":4}]}}
        """

    static let open = """
        {"lead":-2.5,"points":[{"row":0,"col":8,"color":"W"}],"dead_stones":[],"count":null}
        """

    private func state(_ line: String) throws -> GameState {
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un état")
            throw Failure.missing
        }
        return state
    }

    enum Failure: Error { case missing }

    @Test("Une position réglée arrive comptée, avec ses pierres mortes")
    func settled() throws {
        let state = try state(Self.line(estimating: true, estimate: Self.settled))
        #expect(state.estimating == true)
        #expect(state.estimate?.count?.result == "B+5.5")
        #expect(state.estimate?.count?.outcome?.winner == .black)
        #expect(state.estimate?.deadPoints == [Point(row: 4, col: 4)])
        #expect(state.scoring == nil)
    }

    @Test("Une position ouverte arrive avec l'avance de KataGo, sans décompte")
    func open() throws {
        let state = try state(Self.line(estimating: true, estimate: Self.open))
        #expect(state.estimate?.count == nil)
        #expect(state.estimate?.lead == -2.5)
        #expect(state.estimate?.points == [TerritoryPoint(row: 0, col: 8, color: .white)])
    }

    @Test("Demandée mais pas encore arrivée")
    func waiting() throws {
        let state = try state(Self.line(estimating: true, estimate: nil))
        #expect(state.estimating == true)
        #expect(state.estimate == nil)
    }

    @Test("Un pont plus ancien ne dit rien de l'estimation")
    func olderBridge() throws {
        let state = try state(Self.line(estimating: nil, estimate: nil))
        #expect(state.estimating == nil)
        #expect(state.estimate == nil)
    }
}
