import XCTest
@testable import KifuCore

final class GameRecordTests: XCTestCase {
    private func at(_ col: Int, _ row: Int) -> Intersection { Intersection(col: col, row: row) }

    func testEmptyStartMeansBlackToPlayWithoutHandicap() {
        let r = GameRecord(start: Position(size: 19))
        XCTAssertEqual(r.toPlay, .black)
        XCTAssertEqual(r.handicap, 0)
        XCTAssertTrue(r.setupBlack.isEmpty)
        XCTAssertTrue(r.setupWhite.isEmpty)
    }

    func testBlackOnlyStartIsAHandicapAndWhitePlaysFirst() {
        var start = Position(size: 19)
        start[at(3, 3)] = .black; start[at(15, 15)] = .black
        let r = GameRecord(start: start)
        XCTAssertEqual(r.handicap, 2)
        XCTAssertEqual(r.setupBlack, [at(3, 3), at(15, 15)])
        XCTAssertEqual(r.toPlay, .white)
    }

    func testMixedStartIsASetupPositionAndBlackPlaysFirst() {
        var start = Position(size: 19)
        start[at(3, 3)] = .black; start[at(15, 15)] = .white
        let r = GameRecord(start: start)
        XCTAssertEqual(r.handicap, 0)
        XCTAssertEqual(r.setupBlack, [at(3, 3)])
        XCTAssertEqual(r.setupWhite, [at(15, 15)])
        XCTAssertEqual(r.toPlay, .black)
    }

    func testApplyRecordsMovesAndAdvancesPosition() {
        var r = GameRecord(start: Position(size: 9))
        r.apply([Move(color: .black, point: at(4, 4)), Move(color: .white, point: at(2, 2))])
        XCTAssertEqual(r.moves.map(\.move), [Move(color: .black, point: at(4, 4)), Move(color: .white, point: at(2, 2))])
        XCTAssertEqual(r.position[at(4, 4)], .black)
        XCTAssertEqual(r.position[at(2, 2)], .white)
        XCTAssertEqual(r.toPlay, .black)
    }

    func testTakebackToAnEarlierPositionDropsTheMoves() {
        var r = GameRecord(start: Position(size: 9))
        r.apply([Move(color: .black, point: at(4, 4))])
        let afterOne = r.position
        r.apply([Move(color: .white, point: at(2, 2)), Move(color: .black, point: at(6, 6))])
        XCTAssertTrue(r.takeBack(to: afterOne))
        XCTAssertEqual(r.moves.count, 1)
        XCTAssertEqual(r.position, afterOne)
        XCTAssertEqual(r.toPlay, .white)
    }

    func testTakebackToAnUnknownPositionIsRefused() {
        var r = GameRecord(start: Position(size: 9))
        r.apply([Move(color: .black, point: at(4, 4))])
        var other = Position(size: 9); other[at(0, 0)] = .white
        XCTAssertFalse(r.takeBack(to: other))
        XCTAssertEqual(r.moves.count, 1)
    }

    func testForceRecordsAddedStonesAsUncertainMovesAndRemovalsAsErasures() {
        var r = GameRecord(start: Position(size: 9))
        r.apply([Move(color: .black, point: at(4, 4))])
        var seen = r.position
        seen[at(4, 4)] = .empty                 // black stone vanished without a capture
        seen[at(1, 1)] = .white; seen[at(2, 2)] = .white
        r.force(to: seen)
        XCTAssertEqual(r.position, seen)
        XCTAssertEqual(r.moves.count, 3)
        XCTAssertEqual(r.moves[1].move, Move(color: .white, point: at(1, 1)))
        XCTAssertEqual(r.moves[1].erased, [at(4, 4)])
        XCTAssertTrue(r.moves[1].uncertain)
        XCTAssertEqual(r.moves[2].move, Move(color: .white, point: at(2, 2)))
        XCTAssertTrue(r.moves[2].uncertain)
        XCTAssertEqual(r.toPlay, .black)
    }
}
