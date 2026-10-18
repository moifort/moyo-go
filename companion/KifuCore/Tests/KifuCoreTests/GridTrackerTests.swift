import XCTest
import CoreGraphics
import ImageIO
@testable import KifuCore

final class GridTrackerTests: XCTestCase {
    struct Fixture: Decodable {
        let expected: [String]
        let calibration: [[Double]]?
    }

    /// `rasante-support-decale`: the stand shifted the grid by up to 20 px after calibration.
    /// Refitting 8 px at a time, the tracker must move within a few frames, settle, and read
    /// the whole position from where it settles.
    func testTrackerCatchesUpWithADriftedStand() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let json = dir.appendingPathComponent("rasante-support-decale.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: json))
        let start = Calibration(corners: try XCTUnwrap(fixture.calibration).map { Point(x: $0[0], y: $0[1]) })
        let photo = dir.appendingPathComponent("rasante-support-decale.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(photo as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let image = try XCTUnwrap(GrayImage(cgImage: cg))
        let expected = Position(parsing: fixture.expected.joined(separator: "\n"))
        func read(_ calibration: Calibration) -> Position {
            IntersectionReader(geometry: BoardGeometry(calibration: calibration)!).read(image, previous: nil).position
        }
        var tracker = GridTracker(calibration: start, period: 2)
        var updates = 0
        for k in 0..<6 where tracker.update(image, at: Double(k) * 2) != nil { updates += 1 }
        XCTAssertGreaterThan(updates, 0)
        XCTAssertEqual(read(tracker.calibration), expected)
        // Settled: the same frame again moves nothing.
        XCTAssertNil(tracker.update(image, at: 100))
    }

    func testTrackerWaitsForItsPeriod() throws {
        var scene = SyntheticScene()
        scene.stones = [Intersection(col: 3, row: 3): .black]
        let image = scene.render()
        var corners = scene.calibration.corners
        corners[0] = Point(x: corners[0].x + 3, y: corners[0].y)
        var tracker = GridTracker(calibration: Calibration(corners: corners), period: 2)
        XCTAssertNotNil(tracker.update(image, at: 0))
        XCTAssertNil(tracker.update(image, at: 1))
    }
}
