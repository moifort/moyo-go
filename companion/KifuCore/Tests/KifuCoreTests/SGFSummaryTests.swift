import XCTest
@testable import KifuCore

/// The move count shown under each saved game, read from its SGF.
final class SGFSummaryTests: XCTestCase {
    func testCountsMovesAndPasses() {
        XCTAssertEqual(SGFSummary.moveCount(in: "(;GM[1]SZ[19];B[pd];W[dp];B[])"), 3)
    }

    func testIgnoresSemicolonsInsideComments() {
        XCTAssertEqual(SGFSummary.moveCount(in: "(;GM[1]C[début ; fin;B[aa]];B[pd]C[a;b];W[dp])"), 2)
    }

    func testIgnoresSetupAndPlayerNames() {
        XCTAssertEqual(SGFSummary.moveCount(in: "(;GM[1]PB[Bob]PW[Wu]AB[dd][pp]AW[dp];W[qd])"), 1)
    }

    func testEscapedBracketStaysInsideTheValue() {
        XCTAssertEqual(SGFSummary.moveCount(in: #"(;GM[1]C[a \] ;B[aa]];B[pd])"#), 1)
    }
}
