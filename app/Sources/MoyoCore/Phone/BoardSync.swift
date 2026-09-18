import Foundation

/// Turns what the phone sees into the one move the player may have just made.
///
/// The game owns the truth; the phone is only a pair of eyes. A move is accepted
/// when it is the human's turn and exactly one stone of the human's colour appears
/// on the real board where the game has none. Anything else — a missing stone,
/// two new ones, the wrong colour, a stone during the AI's turn — is not a move,
/// and the game is left alone until the board and the game agree again.
public enum BoardSync {
    public static func pendingMove(phone: PhoneBoard, game: GameState) -> Point? {
        guard phone.size == game.size, game.isHumanTurn else { return nil }
        let known = Set(game.stones)
        let seen = Set(phone.stones)
        // Every stone the game knows must be on the real board — the AI's last
        // move included, which the player places before answering it.
        guard known.isSubset(of: seen) else { return nil }
        let added = phone.stones.filter { !known.contains($0) }
        guard added.count == 1, let stone = added.first,
              stone.color == game.toPlay,
              !game.stones.contains(where: { $0.point == stone.point }) else { return nil }
        return stone.point
    }
}
