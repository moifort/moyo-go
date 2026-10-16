import XCTest
@testable import KifuCore

final class PositionTests: XCTestCase {
    func testEmptyPositionHasNoStones() {
        let p = Position(size: 19)
        XCTAssertEqual(p.size, 19)
        XCTAssertEqual(p[Intersection(col: 3, row: 15)], .empty)
        XCTAssertTrue(p.stones.isEmpty)
    }

    func testParseAndDescriptionRoundTrip() {
        let text = """
        .X.
        O..
        ..X
        """
        let p = Position(parsing: text)
        XCTAssertEqual(p.size, 3)
        XCTAssertEqual(p[Intersection(col: 1, row: 0)], .black)
        XCTAssertEqual(p[Intersection(col: 0, row: 1)], .white)
        XCTAssertEqual(p.description, text)
    }

    func testDiffListsChangedIntersections() {
        var a = Position(size: 3)
        var b = a
        a[Intersection(col: 0, row: 0)] = .black
        b[Intersection(col: 2, row: 2)] = .white
        let d = a.diff(to: b)
        XCTAssertEqual(d, [Intersection(col: 0, row: 0): .empty, Intersection(col: 2, row: 2): .white])
    }
}
