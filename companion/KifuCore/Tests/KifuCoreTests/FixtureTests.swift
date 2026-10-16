import XCTest
import CoreGraphics
import ImageIO
@testable import KifuCore

/// Real photos: `name.jpg` next to `name.json` holding the tapped corners and the expected position.
///
///     { "corners": [[x, y], [x, y], [x, y], [x, y]], "lines": 19, "stoneHeight": 0,
///       "expected": ["...", "..."], "ignore": [[col, row], ...] }
///
/// `ignore` lists intersections whose truth is unknown (stones dropped off-grid).
///
/// Corners are in pixels of the photo as stored (origin top-left), order top-left, top-right,
/// bottom-right, bottom-left of the grid as seen in the photo.
final class FixtureTests: XCTestCase {
    struct Fixture: Decodable {
        let corners: [[Double]]
        let lines: Int?
        let stoneHeight: Double?
        let expected: [String]
        let ignore: [[Int]]?
    }

    func testAllFixturesReadCorrectly() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let photos = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { ["jpg", "jpeg", "heic", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if photos.isEmpty { throw XCTSkip("no photo in Fixtures/") }

        var failures: [String] = []
        for photo in photos {
            let name = photo.deletingPathExtension().lastPathComponent
            let json = photo.deletingPathExtension().appendingPathExtension("json")
            guard let data = try? Data(contentsOf: json),
                  let fixture = try? JSONDecoder().decode(Fixture.self, from: data) else {
                failures.append("\(name): missing or invalid .json"); continue
            }
            guard let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = GrayImage(cgImage: cg) else {
                failures.append("\(name): unreadable image"); continue
            }
            let corners = fixture.corners.map { Point(x: $0[0], y: $0[1]) }
            guard let geometry = BoardGeometry(calibration: Calibration(lines: fixture.lines ?? 19, corners: corners)) else {
                failures.append("\(name): degenerate corners"); continue
            }
            var settings = ReaderSettings()
            settings.stoneHeight = fixture.stoneHeight ?? 0
            let readings = IntersectionReader(geometry: geometry, settings: settings).read(image, previous: nil)
            let expected = Position(parsing: fixture.expected.joined(separator: "\n"))
            let ignored = Set((fixture.ignore ?? []).map { Intersection(col: $0[0], row: $0[1]) })
            let wrong = expected.diff(to: readings.position).keys.filter { !ignored.contains($0) }.sorted()
            if !wrong.isEmpty {
                failures.append("\(name): wrong at \(wrong.map(\.description).joined(separator: " "))\nexpected\n\(expected)\nread\n\(readings.position)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n\n"))
    }
}
