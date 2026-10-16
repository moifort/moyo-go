import XCTest
@testable import KifuCore

final class GridDetectorTests: XCTestCase {
    private let corners = SyntheticScene.grazing()

    /// Rough taps: each corner pushed by up to 0.8 spacing in board units, in different directions.
    private func roughTaps(from scene: SyntheticScene) -> [Point] {
        let g = BoardGeometry(calibration: scene.calibration)!
        let n = Double(scene.lines - 1)
        let offsets = [(0.7, 0.5), (-0.6, 0.8), (0.8, -0.7), (-0.5, -0.6)]
        let boardCorners = [(0.0, 0.0), (n, 0.0), (n, n), (0.0, n)]
        return zip(boardCorners, offsets).map { c, o in g.imagePoint(boardX: c.0 + o.0, boardY: c.1 + o.1) }
    }

    private func assertClose(_ found: [Point]?, _ truth: [Point], tolerance: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let found else { return XCTFail("no grid found", file: file, line: line) }
        for (f, c) in zip(found, truth) {
            XCTAssertEqual(f.x, c.x, accuracy: tolerance, file: file, line: line)
            XCTAssertEqual(f.y, c.y, accuracy: tolerance, file: file, line: line)
        }
    }

    func testFindsTheGridFromRoughTapsOnAnEmptyBoard() {
        let scene = SyntheticScene()
        let found = GridDetector.detect(roughCorners: roughTaps(from: scene), lines: 19, in: scene.render())
        assertClose(found, corners, tolerance: 1.5)
    }

    func testFindsTheGridWithStonesShadowAndGradient() {
        var scene = SyntheticScene()
        scene.stones = [Intersection(col: 0, row: 0): .black, Intersection(col: 18, row: 18): .white,
                        Intersection(col: 9, row: 9): .black, Intersection(col: 3, row: 15): .white,
                        Intersection(col: 15, row: 3): .white, Intersection(col: 4, row: 4): .black]
        scene.lighting = { x, y in (0.55 + 0.45 * x / 900) * ((x + y) < 900 ? 0.45 : 1.0) }
        let found = GridDetector.detect(roughCorners: roughTaps(from: scene), lines: 19, in: scene.render())
        assertClose(found, corners, tolerance: 2.0)
    }

    func testExactTapsStayPut() {
        let scene = SyntheticScene()
        let found = GridDetector.detect(roughCorners: corners, lines: 19, in: scene.render())
        assertClose(found, corners, tolerance: 1.0)
    }

    func testUniformImageGivesNothing() {
        let image = GrayImage(width: 900, height: 675, fill: 180)
        XCTAssertNil(GridDetector.detect(roughCorners: corners, lines: 19, in: image))
    }
}
