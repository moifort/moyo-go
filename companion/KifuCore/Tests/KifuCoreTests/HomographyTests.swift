import XCTest
@testable import KifuCore

final class HomographyTests: XCTestCase {
    func testMapsSourceCornersOntoDestinationCorners() throws {
        let src = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
        let dst = [Point(x: 100, y: 200), Point(x: 900, y: 180), Point(x: 820, y: 700), Point(x: 150, y: 650)]
        let h = try XCTUnwrap(Homography(from: src, to: dst))
        for (s, d) in zip(src, dst) {
            let p = h.apply(s)
            XCTAssertEqual(p.x, d.x, accuracy: 1e-6)
            XCTAssertEqual(p.y, d.y, accuracy: 1e-6)
        }
    }

    func testInverseUndoesApply() throws {
        let src = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
        let dst = [Point(x: 100, y: 200), Point(x: 900, y: 180), Point(x: 820, y: 700), Point(x: 150, y: 650)]
        let h = try XCTUnwrap(Homography(from: src, to: dst))
        let inv = try XCTUnwrap(h.inverted())
        let p = Point(x: 0.3, y: 0.7)
        let back = inv.apply(h.apply(p))
        XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
    }

    func testDegenerateCornersGiveNil() {
        let src = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
        let dst = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 2, y: 0), Point(x: 3, y: 0)]
        XCTAssertNil(Homography(from: src, to: dst))
    }
}
