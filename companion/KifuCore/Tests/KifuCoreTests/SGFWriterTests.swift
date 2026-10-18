import XCTest
@testable import KifuCore

final class SGFWriterTests: XCTestCase {
    private func at(_ col: Int, _ row: Int) -> Intersection { Intersection(col: col, row: row) }
    private let date = Date(timeIntervalSince1970: 1_792_000_000)   // 2026-10-14 UTC

    func testEmptyGameHasHeaderOnly() {
        let r = GameRecord(start: Position(size: 19), date: date)
        XCTAssertEqual(SGFWriter.write(r),
                       "(;GM[1]FF[4]CA[UTF-8]AP[Kifu:1.0]SZ[19]DT[2026-10-14]KM[6.5])")
    }

    func testResignationIsWrittenAsTheOpponentsWin() {
        let r = GameRecord(start: Position(size: 19), date: date)
        XCTAssertEqual(SGFWriter.write(r, result: .blackResigned),
                       "(;GM[1]FF[4]CA[UTF-8]AP[Kifu:1.0]SZ[19]DT[2026-10-14]KM[6.5]RE[W+R])")
        XCTAssertTrue(SGFWriter.write(r, result: .whiteResigned).contains("RE[B+R]"))
        XCTAssertFalse(SGFWriter.write(r, result: .finished).contains("RE["))
    }

    func testMovesUseColumnThenRowLetters() {
        var r = GameRecord(start: Position(size: 19), date: date)
        r.apply([Move(color: .black, point: at(15, 3)), Move(color: .white, point: at(3, 15))])
        XCTAssertTrue(SGFWriter.write(r).hasSuffix(";B[pd];W[dp])"))
    }

    func testPassIsAnEmptyMove() {
        var r = GameRecord(start: Position(size: 9), date: date)
        r.apply([Move(color: .black, point: nil), Move(color: .white, point: at(4, 4))])
        XCTAssertTrue(SGFWriter.write(r).hasSuffix(";B[];W[ee])"))
    }

    func testHandicapWritesHAAndSetupStonesAndHalfKomi() {
        var start = Position(size: 19)
        start[at(3, 3)] = .black; start[at(15, 15)] = .black
        let r = GameRecord(start: start, date: date)
        XCTAssertEqual(SGFWriter.write(r),
                       "(;GM[1]FF[4]CA[UTF-8]AP[Kifu:1.0]SZ[19]DT[2026-10-14]HA[2]KM[0.5]AB[dd][pp])")
    }

    func testMixedSetupWritesABAndAW() {
        var start = Position(size: 9)
        start[at(0, 0)] = .black; start[at(8, 8)] = .white
        let r = GameRecord(start: start, date: date)
        XCTAssertTrue(SGFWriter.write(r).hasSuffix("KM[6.5]AB[aa]AW[ii])"))
    }

    func testUncertainMoveCarriesCommentAndErasures() {
        var r = GameRecord(start: Position(size: 9), date: date)
        r.apply([Move(color: .black, point: at(4, 4))])
        var seen = r.position
        seen[at(4, 4)] = .empty; seen[at(1, 1)] = .white
        r.force(to: seen)
        XCTAssertTrue(SGFWriter.write(r).hasSuffix(";B[ee];W[bb]AE[ee]C[ordre incertain])"))
    }
}
