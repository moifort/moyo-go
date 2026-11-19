import Network
import XCTest
import dnssd
@testable import KifuCore

/// When Bonjour cannot advertise the phone, Kifu says why on screen: otherwise the Mac
/// never sees it and nothing tells the player.
final class AdvertisingTests: XCTestCase {
    func testLocalNetworkRefusedPointsToTheSetting() {
        let message = BoardBroadcast.advertisingProblem(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied)))
        XCTAssertTrue(message.contains("Réseau local"), message)
    }

    func testOtherFailuresSayMoyoCannotSeeThePhone() {
        let message = BoardBroadcast.advertisingProblem(.posix(.EADDRINUSE))
        XCTAssertTrue(message.hasPrefix("Moyo ne peut pas voir ce téléphone"), message)
    }
}
