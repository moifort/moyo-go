import Foundation
import Testing

@testable import MoyoCore

/// Kifu records a game between two people and asks the Mac to follow it. Whatever
/// the window had open, the phone's board is what it shows.
@MainActor
@Suite("Suivre la partie du téléphone")
struct FollowPhoneTests {
    private func session() -> GameSession {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        // The bridge is never started: `send` is a no-op, which is all these tests need.
        return GameSession(store: SettingsStore(defaults: defaults, key: "test.settings"))
    }

    private static let ready = BridgeEvent.ready(katago: nil, model: nil, strategies: [], settings: [:])

    private static let kifuLine = """
        {"follow":true,"next":"W","rows":["X..","...","..O"],"size":3,"status":"locked"}
        """

    @Test("Kifu demande à être suivi et dit qui a le trait")
    func decodesFollowAndNext() throws {
        let board = try #require(PhoneBoard(line: Self.kifuLine))
        #expect(board.follow)
        #expect(board.next == .white)
    }

    @Test("GoBoardVision ne demande rien : le plateau reste lu comme des coups")
    func goBoardVisionIsNotFollowed() throws {
        let board = try #require(PhoneBoard(line: "{\"size\":3,\"rows\":[\"X..\",\"...\",\"...\"]}"))
        #expect(!board.follow)
        #expect(board.next == nil)
    }

    @Test("La position devient un enregistrement en pierres posées, avec le trait")
    func writesSetupRecord() {
        let board = PhoneBoard(
            size: 19,
            stones: [
                Stone(row: 3, col: 15, color: .black),
                Stone(row: 0, col: 0, color: .black),
                Stone(row: 16, col: 2, color: .white),
            ],
            follow: true,
            next: .white
        )
        #expect(
            PhoneRecord.sgf(board, komi: 6.5, event: "En direct")
                == "(;GM[1]FF[4]CA[UTF-8]SZ[19]KM[6.5]EV[En direct]PL[W]AB[pd][aa]AW[cq])"
        )
    }

    @Test("Le plateau suivi remplace la partie ouverte, même sans rapport avec elle")
    func replacesOpenGame() {
        let session = session()
        session.handle(Self.ready)
        #expect(session.recordName == nil)

        session.phone.consume(Data((Self.kifuLine + "\n").utf8))
        #expect(session.isFollowingPhone)
        #expect(session.recordName == "Téléphone")
    }

    @Test("Un plateau suivi avant le moteur attend qu'il soit prêt")
    func heldUntilReady() {
        let session = session()
        session.phone.consume(Data((Self.kifuLine + "\n").utf8))
        #expect(session.hasRecordWaiting)
        session.handle(Self.ready)
        #expect(!session.hasRecordWaiting)
        #expect(session.isFollowingPhone)
    }

    @Test("Une nouvelle partie cesse de suivre jusqu'au prochain plateau")
    func newGameStopsFollowing() {
        let session = session()
        session.handle(Self.ready)
        session.phone.consume(Data((Self.kifuLine + "\n").utf8))
        session.newGame()
        #expect(!session.isFollowingPhone)
        session.phone.consume(Data(Self.kifuLine.replacingOccurrences(of: "\"...\"", with: "\".X.\"").appending("\n").utf8))
        #expect(session.isFollowingPhone)
    }
}
