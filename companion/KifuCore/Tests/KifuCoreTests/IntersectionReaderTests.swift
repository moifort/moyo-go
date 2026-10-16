import XCTest
@testable import KifuCore

final class IntersectionReaderTests: XCTestCase {
    private func at(_ col: Int, _ row: Int) -> Intersection { Intersection(col: col, row: row) }

    /// Stones spread over corners, edges, centre and the compressed far rows.
    private let stones: [Intersection: Stone] = [
        Intersection(col: 0, row: 0): .black, Intersection(col: 18, row: 0): .black,
        Intersection(col: 0, row: 18): .white, Intersection(col: 18, row: 18): .white,
        Intersection(col: 9, row: 9): .black, Intersection(col: 9, row: 3): .white,
        Intersection(col: 5, row: 1): .black, Intersection(col: 6, row: 1): .white,
        Intersection(col: 12, row: 0): .white, Intersection(col: 3, row: 15): .black,
        Intersection(col: 4, row: 15): .black, Intersection(col: 4, row: 16): .white,
    ]

    private func expected(_ stones: [Intersection: Stone]) -> Position {
        var p = Position(size: 19)
        for (i, s) in stones { p[i] = s }
        return p
    }

    private func reader(for scene: SyntheticScene, height: Double = 0) -> IntersectionReader {
        var settings = ReaderSettings()
        settings.stoneHeight = height
        return IntersectionReader(geometry: BoardGeometry(calibration: scene.calibration)!, settings: settings)
    }

    func testEmptyBoardReadsAllEmpty() {
        let scene = SyntheticScene()
        let readings = reader(for: scene).read(scene.render(), previous: nil)
        XCTAssertEqual(readings.position, Position(size: 19))
        XCTAssertTrue(readings.unreadable.isEmpty)
    }

    func testFlatStonesAreReadAtTheirIntersections() {
        var scene = SyntheticScene()
        scene.stones = stones
        let readings = reader(for: scene).read(scene.render(), previous: nil)
        XCTAssertEqual(readings.position, expected(stones))
    }

    func testThickStonesAreReadWhereTheirTopsAppear() {
        var scene = SyntheticScene()
        scene.stones = stones
        scene.stoneHeight = 0.35
        let readings = reader(for: scene, height: 0.35).read(scene.render(), previous: nil)
        XCTAssertEqual(readings.position, expected(stones))
    }

    func testStoneLiftGrowsTowardsTheFarEdge() {
        let r = reader(for: SyntheticScene(), height: 0.35)
        let near = r.stoneLift(at: at(9, 18)), far = r.stoneLift(at: at(9, 0))
        XCTAssertGreaterThan(far, near)
        XCTAssertGreaterThanOrEqual(near, 0)
        XCTAssertLessThan(far, 1.0)
    }

    func testGradientAndHardShadowDoNotChangeTheReading() {
        var scene = SyntheticScene()
        scene.stones = stones
        scene.lighting = { x, y in
            let gradient = 0.55 + 0.45 * x / 900
            let shadow = (x + y) < 900 ? 0.45 : 1.0
            return gradient * shadow
        }
        let readings = reader(for: scene).read(scene.render(), previous: nil)
        XCTAssertEqual(readings.position, expected(stones))
    }

    func testClassifyKeepsAnExistingStoneInTheHysteresisBand() {
        let s = ReaderSettings()
        func m(_ stone: Double, wood: Double = 100) -> IntersectionReader.Measure { .init(stone: stone, wood: wood, deviation: 0) }
        XCTAssertEqual(IntersectionReader.classify(m(62), previous: .black, settings: s), .black)
        XCTAssertEqual(IntersectionReader.classify(m(62), previous: .empty, settings: s), .empty)
        XCTAssertEqual(IntersectionReader.classify(m(110), previous: .white, settings: s), .white)
        XCTAssertEqual(IntersectionReader.classify(m(110), previous: nil, settings: s), .empty)
        XCTAssertEqual(IntersectionReader.classify(m(40), previous: .white, settings: s), .black)
    }

    func testClassifyUsesHeadroomWhenTheWoodIsAlreadyBright() {
        let s = ReaderSettings()
        let sunlit = IntersectionReader.Measure(stone: 250, wood: 225, deviation: 0)   // ratio 1.11, headroom 0.83
        XCTAssertEqual(IntersectionReader.classify(sunlit, previous: nil, settings: s), .white)
        let shaded = IntersectionReader.Measure(stone: 160, wood: 100, deviation: 0)   // ratio 1.6
        XCTAssertEqual(IntersectionReader.classify(shaded, previous: nil, settings: s), .white)
    }

    func testNoisyPatchIsUnreadable() {
        let scene = SyntheticScene()
        var image = scene.render()
        let g = BoardGeometry(calibration: scene.calibration)!
        let c = g.imagePoint(of: at(9, 14))
        var seed: UInt32 = 7
        for y in Int(c.y) - 25...Int(c.y) + 25 {
            for x in Int(c.x) - 25...Int(c.x) + 25 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                image.set(x: x, y: y, value: (seed >> 24) & 1 == 0 ? 0 : 255)
            }
        }
        let readings = reader(for: scene).read(image, previous: nil)
        XCTAssertTrue(readings.unreadable.contains(at(9, 14)))
    }
}

final class StabilityFilterTests: XCTestCase {
    private func at(_ col: Int, _ row: Int) -> Intersection { Intersection(col: col, row: row) }

    private func readings(_ stones: [Intersection: Stone], unreadable: Set<Intersection> = []) -> Readings {
        var p = Position(size: 9)
        for (i, s) in stones { p[i] = s }
        return Readings(position: p, unreadable: unreadable)
    }

    func testChangeIsAcceptedAfterRequiredIdenticalFrames() {
        var f = StabilityFilter(start: Position(size: 9), required: 3)
        let seen = readings([at(4, 4): .black])
        XCTAssertEqual(f.push(seen), Position(size: 9))
        XCTAssertEqual(f.push(seen), Position(size: 9))
        var expected = Position(size: 9); expected[at(4, 4)] = .black
        XCTAssertEqual(f.push(seen), expected)
    }

    func testOneFrameFlickerResetsTheStreak() {
        var f = StabilityFilter(start: Position(size: 9), required: 3)
        let seen = readings([at(4, 4): .black])
        _ = f.push(seen); _ = f.push(seen)
        _ = f.push(readings([:]))
        XCTAssertEqual(f.push(seen), Position(size: 9))
        XCTAssertEqual(f.push(seen), Position(size: 9))
        XCTAssertNotEqual(f.push(seen), Position(size: 9))
    }

    func testUnreadableFrameResetsTheStreakAndKeepsTheStableValue() {
        var start = Position(size: 9); start[at(2, 2)] = .white
        var f = StabilityFilter(start: start, required: 2)
        _ = f.push(readings([at(2, 2): .white, at(4, 4): .black]))
        let blocked = f.push(readings([at(4, 4): .black], unreadable: [at(2, 2), at(4, 4)]))
        XCTAssertEqual(blocked, start)
        _ = f.push(readings([at(2, 2): .white, at(4, 4): .black]))
        var expected = start; expected[at(4, 4)] = .black
        XCTAssertEqual(f.push(readings([at(2, 2): .white, at(4, 4): .black])), expected)
    }

    func testResetAdoptsANewAcceptedPosition() {
        var f = StabilityFilter(start: Position(size: 9), required: 3)
        var accepted = Position(size: 9); accepted[at(1, 1)] = .black
        f.reset(to: accepted)
        XCTAssertEqual(f.push(readings([:])), accepted)
    }
}
