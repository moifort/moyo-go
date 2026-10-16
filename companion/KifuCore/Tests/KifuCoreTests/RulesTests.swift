import XCTest
@testable import KifuCore

final class RulesTests: XCTestCase {
    private func pos(_ text: String) -> Position { Position(parsing: text) }
    private func at(_ col: Int, _ row: Int) -> Intersection { Intersection(col: col, row: row) }

    func testPlayOnEmptyPointAddsStone() throws {
        let p = Position(size: 5)
        let next = try XCTUnwrap(Rules.play(Move(color: .black, point: at(2, 2)), on: p))
        XCTAssertEqual(next[at(2, 2)], .black)
    }

    func testPlayOnOccupiedPointIsIllegal() {
        var p = Position(size: 5)
        p[at(2, 2)] = .white
        XCTAssertNil(Rules.play(Move(color: .black, point: at(2, 2)), on: p))
    }

    func testPassLeavesPositionUnchanged() {
        let p = pos("""
        .X.
        ...
        ...
        """)
        XCTAssertEqual(Rules.play(Move(color: .white, point: nil), on: p), p)
    }

    func testCapturesSingleStone() throws {
        let p = pos("""
        .X...
        XOX..
        .....
        .....
        .....
        """)
        let next = try XCTUnwrap(Rules.play(Move(color: .black, point: at(1, 2)), on: p))
        XCTAssertEqual(next, pos("""
        .X...
        X.X..
        .X...
        .....
        .....
        """))
    }

    func testCapturesTwoGroupsAtOnce() throws {
        let p = pos("""
        .....
        .XXX.
        XO.OX
        .XXX.
        .....
        """)
        let next = try XCTUnwrap(Rules.play(Move(color: .black, point: at(2, 2)), on: p))
        XCTAssertEqual(next, pos("""
        .....
        .XXX.
        X.X.X
        .XXX.
        .....
        """))
    }

    func testSuicideIsIllegal() {
        let p = pos("""
        .X...
        X.X..
        .X...
        .....
        .....
        """)
        XCTAssertNil(Rules.play(Move(color: .white, point: at(1, 1)), on: p))
    }

    func testMoveWithoutOwnLibertiesIsLegalWhenItCaptures() throws {
        let p = pos("""
        OX...
        .O...
        OX...
        .....
        .....
        """)
        let next = try XCTUnwrap(Rules.play(Move(color: .black, point: at(0, 1)), on: p))
        XCTAssertEqual(next, pos("""
        .X...
        XO...
        OX...
        .....
        .....
        """))
    }
}

final class ExplainTests: XCTestCase {
    private func pos(_ text: String) -> Position { Position(parsing: text) }
    private func at(_ col: Int, _ row: Int) -> Intersection { Intersection(col: col, row: row) }

    func testNoChangeExplainsAsNoMove() {
        let p = Position(size: 5)
        XCTAssertEqual(Rules.explain(from: p, to: p, toPlay: .black), [])
    }

    func testOneStoneOfSideToPlayIsOneMove() {
        let a = Position(size: 5)
        var b = a; b[at(2, 2)] = .black
        XCTAssertEqual(Rules.explain(from: a, to: b, toPlay: .black), [Move(color: .black, point: at(2, 2))])
    }

    func testOneStoneOfOtherSideImpliesAPass() {
        let a = Position(size: 5)
        var b = a; b[at(2, 2)] = .white
        XCTAssertEqual(Rules.explain(from: a, to: b, toPlay: .black),
                       [Move(color: .black, point: nil), Move(color: .white, point: at(2, 2))])
    }

    func testTwoStonesOfDifferentColoursAreOrderedBySideToPlay() {
        let a = Position(size: 5)
        var b = a; b[at(2, 2)] = .black; b[at(3, 3)] = .white
        XCTAssertEqual(Rules.explain(from: a, to: b, toPlay: .black),
                       [Move(color: .black, point: at(2, 2)), Move(color: .white, point: at(3, 3))])
        XCTAssertEqual(Rules.explain(from: a, to: b, toPlay: .white),
                       [Move(color: .white, point: at(3, 3)), Move(color: .black, point: at(2, 2))])
    }

    func testTwoStonesOfSameColourCannotBeExplained() {
        let a = Position(size: 5)
        var b = a; b[at(2, 2)] = .black; b[at(3, 3)] = .black
        XCTAssertNil(Rules.explain(from: a, to: b, toPlay: .black))
    }

    func testThreeStonesCannotBeExplained() {
        let a = Position(size: 5)
        var b = a; b[at(2, 2)] = .black; b[at(3, 3)] = .white; b[at(1, 1)] = .black
        XCTAssertNil(Rules.explain(from: a, to: b, toPlay: .black))
    }

    func testCaptureIsExplainedOnceCapturedStonesAreGone() {
        let a = pos("""
        .X...
        XOX..
        .....
        .....
        .....
        """)
        let b = pos("""
        .X...
        X.X..
        .X...
        .....
        .....
        """)
        XCTAssertEqual(Rules.explain(from: a, to: b, toPlay: .black), [Move(color: .black, point: at(1, 2))])
    }

    func testCaptureWithStonesStillOnBoardWaits() {
        let a = pos("""
        .X...
        XOX..
        .....
        .....
        .....
        """)
        let b = pos("""
        .X...
        XOX..
        .X...
        .....
        .....
        """)
        XCTAssertNil(Rules.explain(from: a, to: b, toPlay: .black))
    }

    func testStoneRemovedWithoutCaptureCannotBeExplained() {
        var a = Position(size: 5); a[at(2, 2)] = .black
        let b = Position(size: 5)
        XCTAssertNil(Rules.explain(from: a, to: b, toPlay: .white))
    }

    func testColourChangeCannotBeExplained() {
        var a = Position(size: 5); a[at(2, 2)] = .black
        var b = Position(size: 5); b[at(2, 2)] = .white
        XCTAssertNil(Rules.explain(from: a, to: b, toPlay: .white))
    }
}
