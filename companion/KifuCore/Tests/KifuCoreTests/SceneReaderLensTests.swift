import XCTest
import CoreGraphics
import ImageIO
@testable import KifuCore

final class SceneReaderLensTests: XCTestCase {
    struct Fixture: Decodable {
        let corners: [[Double]]
        let calibration: [[Double]]
        let expected: [String]
    }

    /// `Suivi/rasante-grille-glissee`: the tracker slid 3 px on a dense board. Read from those
    /// corners alone the camera is lost; with the lens of the calibration, every stone is read.
    func testAGridRefittedOffKeepsTheLensOfTheCalibration() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("Suivi")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: dir.appendingPathComponent("rasante-grille-glissee.json")))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(dir.appendingPathComponent("rasante-grille-glissee.jpg") as CFURL, nil))
        let image = try XCTUnwrap(GrayImage(cgImage: try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))))
        func calibration(_ corners: [[Double]]) -> Calibration { Calibration(corners: corners.map { Point(x: $0[0], y: $0[1]) }) }

        let calibrated = try XCTUnwrap(SceneReader(calibration: calibration(fixture.calibration), imageWidth: image.width, imageHeight: image.height))
        let focal = try XCTUnwrap(calibrated.focal)
        let slid = try XCTUnwrap(SceneReader(calibration: calibration(fixture.corners), imageWidth: image.width, imageHeight: image.height, focal: focal))
        XCTAssertNotNil(slid.camera)
        let expected = Position(parsing: fixture.expected.joined(separator: "\n"))
        let wrong = expected.diff(to: slid.read(image, previous: nil).position).keys.sorted()
        XCTAssertTrue(wrong.isEmpty, "wrong at \(wrong.map(\.description).joined(separator: " "))")
    }
}
