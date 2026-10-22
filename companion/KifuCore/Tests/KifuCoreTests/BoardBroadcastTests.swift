import XCTest
@testable import KifuCore

final class BoardBroadcastTests: XCTestCase {
    private struct Wire: Decodable { let size: Int; let rows: [String]; let status: String; let follow: Bool; let next: String }

    func testLineIsOneJSONObjectInMoyoFormat() throws {
        var p = Position(size: 19)
        p[Intersection(col: 3, row: 0)] = .black
        p[Intersection(col: 15, row: 18)] = .white
        let data = BoardBroadcast.line(position: p, status: .inSync, toPlay: .white, viewpoint: .leftPlayer)
        XCTAssertEqual(data.last, UInt8(ascii: "\n"))
        XCTAssertEqual(data.filter { $0 == UInt8(ascii: "\n") }.count, 1)
        let wire = try JSONDecoder().decode(Wire.self, from: data.dropLast())
        XCTAssertEqual(wire.size, 19)
        XCTAssertEqual(wire.rows.count, 19)
        XCTAssertEqual(wire.rows, BoardBroadcast.Viewpoint.leftPlayer.orient(p).description.split(separator: "\n").map(String.init))
        XCTAssertEqual(wire.status, "locked")
        XCTAssertTrue(wire.follow)
        XCTAssertEqual(wire.next, "W")
    }

    /// Image (row 0 = far edge, last row = phone edge):
    ///   X..      far edge
    ///   ...
    ///   ..O      phone edge
    func testLeftPlayerHasImageLeftEdgeAtBottomAndPhoneOnTheRight() {
        let p = Position(parsing: "X..\n...\n..O")
        XCTAssertEqual(BoardBroadcast.Viewpoint.leftPlayer.orient(p).description, "..O\n...\nX..")
        // Black, at the image's top-left (far edge, left player's edge): bottom-left for the left player.
        let q = Position(parsing: "X..\n...\n...")
        XCTAssertEqual(BoardBroadcast.Viewpoint.leftPlayer.orient(q).description, "...\n...\nX..")
        // A stone at the phone's edge, left player's side: bottom-right for them.
        let r = Position(parsing: "...\n...\nX..")
        XCTAssertEqual(BoardBroadcast.Viewpoint.leftPlayer.orient(r).description, "...\n...\n..X")
    }

    func testRightPlayerHasImageRightEdgeAtBottomAndPhoneOnTheLeft() {
        // Top-right of the image (far edge, right player's edge): bottom-right for the right player.
        let q = Position(parsing: "..X\n...\n...")
        XCTAssertEqual(BoardBroadcast.Viewpoint.rightPlayer.orient(q).description, "...\n...\n..X")
        // Bottom-right of the image (phone edge, right player's side): bottom-left for them.
        let r = Position(parsing: "...\n...\n..X")
        XCTAssertEqual(BoardBroadcast.Viewpoint.rightPlayer.orient(r).description, "...\n...\nX..")
    }

    func testTheTwoViewpointsAreAHalfTurnApart() {
        let p = Position(parsing: "XO.\n.X.\nO..")
        let left = BoardBroadcast.Viewpoint.leftPlayer.orient(p).description
        let right = BoardBroadcast.Viewpoint.rightPlayer.orient(p).description
        XCTAssertEqual(String(left.reversed()), right)
    }

    private struct HistoryWire: Decodable {
        struct History: Decodable {
            struct Move: Decodable { let color: String; let point: [Int]?; let erased: [[Int]]? }
            let setup: [String: [[Int]]]
            let moves: [Move]
        }
        let history: History?
        let rows: [String]
    }

    func testANewcomerGetsTheMovesInTheBoardsOrientation() throws {
        var record = GameRecord(start: Position(parsing: "...\n...\nX.."))
        record.apply([Move(color: .white, point: Intersection(col: 2, row: 0)), Move(color: .black, point: nil)])
        let data = BoardBroadcast.line(
            position: record.position, status: .inSync, toPlay: record.toPlay, viewpoint: .leftPlayer, history: record)
        let wire = try JSONDecoder().decode(HistoryWire.self, from: data.dropLast())
        let history = try XCTUnwrap(wire.history)
        // Every point lands where `rows` shows its stone.
        XCTAssertEqual(history.setup["B"], [[2, 2]])
        XCTAssertEqual(history.setup["W"], [])
        XCTAssertEqual(wire.rows, ["O..", "...", "..X"])
        XCTAssertEqual(history.moves.count, 2)
        XCTAssertEqual(history.moves[0].color, "W")
        let point = try XCTUnwrap(history.moves[0].point)
        XCTAssertEqual(Array(wire.rows[point[0]])[point[1]], "O")
        XCTAssertEqual(history.moves[1].color, "B")
        XCTAssertNil(history.moves[1].point)
        XCTAssertNil(history.moves[0].erased)
    }

    func testErasedStonesTravelWithTheirMove() throws {
        var record = GameRecord(start: Position(parsing: "X..\n...\n..."))
        record.force(to: Position(parsing: "...\n.O.\n..."))
        let data = BoardBroadcast.line(
            position: record.position, status: .inSync, toPlay: record.toPlay, viewpoint: .rightPlayer, history: record)
        let history = try XCTUnwrap(JSONDecoder().decode(HistoryWire.self, from: data.dropLast()).history)
        XCTAssertEqual(history.moves.first?.erased, [[0, 2]])
    }

    func testPointsTurnLikeTheBoard() {
        let size = 5
        for viewpoint in BoardBroadcast.Viewpoint.allCases {
            for row in 0..<size {
                for col in 0..<size {
                    var p = Position(size: size)
                    let point = Intersection(col: col, row: row)
                    p[point] = .black
                    XCTAssertEqual(viewpoint.orient(p)[viewpoint.orient(point, size: size)], .black)
                }
            }
        }
    }

    func testOrdinaryLinesCarryNoHistory() throws {
        let data = BoardBroadcast.line(position: Position(size: 9), status: .inSync, toPlay: .black, viewpoint: .leftPlayer)
        XCTAssertNil(try JSONDecoder().decode(HistoryWire.self, from: data.dropLast()).history)
    }

    func testStatusNames() {
        XCTAssertEqual(BoardBroadcast.statusName(.inSync), "locked")
        XCTAssertEqual(BoardBroadcast.statusName(.pending), "uncertain")
        XCTAssertEqual(BoardBroadcast.statusName(.awaitingCaptureRemoval), "uncertain")
    }
}
