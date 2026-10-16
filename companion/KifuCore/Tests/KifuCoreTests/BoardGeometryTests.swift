import XCTest
@testable import KifuCore

final class BoardGeometryTests: XCTestCase {
    private let corners = SyntheticScene.grazing()

    func testCornersProjectOntoCalibrationCorners() throws {
        let g = try XCTUnwrap(BoardGeometry(calibration: Calibration(lines: 19, corners: corners)))
        let tl = g.imagePoint(of: Intersection(col: 0, row: 0))
        let br = g.imagePoint(of: Intersection(col: 18, row: 18))
        XCTAssertEqual(tl.x, corners[0].x, accuracy: 1e-6); XCTAssertEqual(tl.y, corners[0].y, accuracy: 1e-6)
        XCTAssertEqual(br.x, corners[2].x, accuracy: 1e-6); XCTAssertEqual(br.y, corners[2].y, accuracy: 1e-6)
    }

    func testMinSpacingIsAtTheFarEdge() throws {
        let g = try XCTUnwrap(BoardGeometry(calibration: Calibration(lines: 19, corners: corners)))
        let farStep = (corners[1].x - corners[0].x) / 18
        XCTAssertLessThan(g.minSpacing, farStep + 0.5)
        XCTAssertGreaterThan(g.minSpacing, 5)
    }

    func testAwayFromCameraPointsTowardsTheNarrowEdge() throws {
        let g = try XCTUnwrap(BoardGeometry(calibration: Calibration(lines: 19, corners: corners)))
        XCTAssertEqual(g.awayFromCamera.0, 0, accuracy: 1e-9)
        XCTAssertEqual(g.awayFromCamera.1, -1, accuracy: 1e-9)
        // Rotated 90°: camera on the left, far edge on the right.
        let rotated = [Point(x: 100, y: 100), Point(x: 1100, y: 300), Point(x: 1100, y: 600), Point(x: 100, y: 800)]
        let r = try XCTUnwrap(BoardGeometry(calibration: Calibration(lines: 19, corners: rotated)))
        XCTAssertEqual(r.awayFromCamera.0, 1, accuracy: 1e-9)
        XCTAssertEqual(r.awayFromCamera.1, 0, accuracy: 1e-9)
    }

    func testDegenerateCalibrationIsRejected() {
        let flat = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 2, y: 0), Point(x: 3, y: 0)]
        XCTAssertNil(BoardGeometry(calibration: Calibration(lines: 19, corners: flat)))
    }

    func testRefineCornersSnapsTapsBackOntoTheGrid() throws {
        let scene = SyntheticScene()
        let image = scene.render()
        let offsets = [Point(x: 4, y: -3), Point(x: -3, y: 4), Point(x: 3, y: 3), Point(x: -4, y: -2)]
        let taps = zip(corners, offsets).map { Point(x: $0.x + $1.x, y: $0.y + $1.y) }
        let refined = BoardGeometry.refineCorners(taps, lines: 19, in: image, radius: 6)
        for (r, c) in zip(refined, corners) {
            XCTAssertEqual(r.x, c.x, accuracy: 1.0)
            XCTAssertEqual(r.y, c.y, accuracy: 1.0)
        }
    }

    func testRefineCornersLeavesACornerCoveredByAStoneAlone() throws {
        var scene = SyntheticScene()
        scene.stones = [Intersection(col: 0, row: 18): .white]
        let image = scene.render()
        let taps = corners.enumerated().map { i, c in i == 3 ? Point(x: c.x + 3, y: c.y - 2) : c }
        let refined = BoardGeometry.refineCorners(taps, lines: 19, in: image, radius: 6)
        XCTAssertEqual(refined[3].x, taps[3].x, accuracy: 1e-9)
        XCTAssertEqual(refined[3].y, taps[3].y, accuracy: 1e-9)
    }
}
