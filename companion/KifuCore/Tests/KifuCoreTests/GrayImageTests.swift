import XCTest
@testable import KifuCore

final class GrayImageTests: XCTestCase {
    func testSubscriptAndSet() {
        var img = GrayImage(width: 4, height: 3, fill: 200)
        XCTAssertEqual(img[3, 2], 200)
        img.set(x: 3, y: 2, value: 7)
        XCTAssertEqual(img[3, 2], 7)
    }

    func testBilinearSampleInterpolatesBetweenPixels() {
        var img = GrayImage(width: 2, height: 1, fill: 0)
        img.set(x: 1, y: 0, value: 100)
        XCTAssertEqual(img.sample(x: 0.5, y: 0), 50, accuracy: 0.01)
        XCTAssertEqual(img.sample(x: 0.25, y: 0), 25, accuracy: 0.01)
    }

    func testSampleOutsideImageClampsToBorder() {
        let img = GrayImage(width: 3, height: 3, fill: 77)
        XCTAssertEqual(img.sample(x: -5, y: 10), 77, accuracy: 0.01)
    }
}
