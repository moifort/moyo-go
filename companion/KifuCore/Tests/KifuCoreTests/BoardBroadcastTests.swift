import XCTest
@testable import KifuCore

final class BoardBroadcastTests: XCTestCase {
    private struct Wire: Decodable { let size: Int; let rows: [String]; let status: String }

    func testLineIsOneJSONObjectInMoyoFormat() throws {
        var p = Position(size: 19)
        p[Intersection(col: 3, row: 0)] = .black
        p[Intersection(col: 15, row: 18)] = .white
        let data = BoardBroadcast.line(position: p, status: .inSync)
        XCTAssertEqual(data.last, UInt8(ascii: "\n"))
        XCTAssertEqual(data.filter { $0 == UInt8(ascii: "\n") }.count, 1)
        let wire = try JSONDecoder().decode(Wire.self, from: data.dropLast())
        XCTAssertEqual(wire.size, 19)
        XCTAssertEqual(wire.rows.count, 19)
        XCTAssertEqual(wire.rows[0], "...X...............")
        XCTAssertEqual(wire.rows[18], "...............O...")
        XCTAssertEqual(wire.status, "locked")
    }

    func testStatusNames() {
        XCTAssertEqual(BoardBroadcast.statusName(.inSync), "locked")
        XCTAssertEqual(BoardBroadcast.statusName(.pending), "uncertain")
        XCTAssertEqual(BoardBroadcast.statusName(.awaitingCaptureRemoval), "uncertain")
        XCTAssertEqual(BoardBroadcast.statusName(.lost), "uncertain")
    }
}
