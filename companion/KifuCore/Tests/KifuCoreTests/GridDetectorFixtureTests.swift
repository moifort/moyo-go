import XCTest
import CoreGraphics
import ImageIO
@testable import KifuCore

/// Real frames with rough taps: the detector must land within a few pixels of the checked corners.
final class GridDetectorFixtureTests: XCTestCase {
    struct Fixture: Decodable {
        let lines: Int?
        let taps: [[Double]]?
        let corners: [[Double]]
    }

    static let tolerance = 8.0

    func testDetectorRecoversCheckedCornersFromRoughTaps() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let jsons = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var tested = 0
        var failures: [String] = []
        for json in jsons {
            guard let data = try? Data(contentsOf: json),
                  let fixture = try? JSONDecoder().decode(Fixture.self, from: data),
                  let taps = fixture.taps else { continue }
            let name = json.deletingPathExtension().lastPathComponent
            guard let photo = ["png", "jpg", "jpeg"].map({ json.deletingPathExtension().appendingPathExtension($0) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let image = GrayImage(cgImage: cg) else { failures.append("\(name): unreadable image"); continue }
            tested += 1
            let rough = taps.map { Point(x: $0[0], y: $0[1]) }
            guard let found = GridDetector.detect(roughCorners: rough, lines: fixture.lines ?? 19, in: image) else {
                failures.append("\(name): grid not found"); continue
            }
            for (f, c) in zip(found, fixture.corners) {
                let d = ((f.x - c[0]) * (f.x - c[0]) + (f.y - c[1]) * (f.y - c[1])).squareRoot()
                if d > Self.tolerance { failures.append(String(format: "%@: corner %.1f,%.1f is %.1f px from %.1f,%.1f", name, f.x, f.y, d, c[0], c[1])) }
            }
        }
        if tested == 0 { throw XCTSkip("no fixture with taps") }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
