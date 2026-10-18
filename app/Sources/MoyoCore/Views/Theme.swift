import SwiftUI

/// The app's own palette. It does not follow the system appearance: a board reads
/// better on a dark surface, and glass over a light background turns milky.
public enum Theme {
    public static let windowBackground = Color(red: 0.133, green: 0.122, blue: 0.106)
    public static let wood = Color(red: 0.874, green: 0.745, blue: 0.545)
    public static let gridLine = Color(red: 0.290, green: 0.220, blue: 0.137)
    public static let blackStone = Color(red: 0.102, green: 0.090, blue: 0.078)
    public static let whiteStone = Color(red: 0.969, green: 0.961, blue: 0.945)

    /// Lifts the sidebar slightly off the window background so its glass reads as
    /// glass rather than as a flat panel.
    public static let sidebarVeil = Color.white.opacity(0.06)

    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.55)
    public static let hairline = Color.white.opacity(0.14)

    /// The chart is read from the human player's side: white when they are ahead,
    /// red when they are behind, the way Stocks colours a move against you.
    public static let chartAhead = Color.white
    public static let chartBehind = Color(red: 0.847, green: 0.271, blue: 0.247)
    /// The area between the line and the midline: present, but well behind the line.
    public static let chartAheadFill = Color.white.opacity(0.22)
    public static let chartBehindFill = Color(red: 0.847, green: 0.271, blue: 0.247).opacity(0.3)
    public static let chartMidline = Color.white.opacity(0.25)

    /// A small capsule that names a setting: the level of the opponent, the
    /// phone that is connected.
    public static let tagBackground = Color.white.opacity(0.12)
    /// The phone is live: the one green in the sidebar, so it is seen.
    public static let connected = Color(red: 0.30, green: 0.78, blue: 0.42)
    /// A position from the phone that no move explains: amber, a wait rather than a fault.
    public static let warning = Color(red: 0.93, green: 0.66, blue: 0.25)

    public static func stone(_ color: PlayerColor) -> Color {
        color == .black ? blackStone : whiteStone
    }

    /// A stone agreed to be dead is not removed, it dims — but only slightly. Faded
    /// too far it settles onto the wood, and a black stone and a white one end up the
    /// same beige disc; the player has to keep seeing whose stone they are giving up.
    /// The territory mark at its centre is what says the point is being counted.
    public static let deadStoneOpacity: Double = 0.65
    /// A dimmed white stone on light wood needs a contour to keep its edge.
    public static let deadStoneContour = gridLine.opacity(0.35)

    /// KataGo's first choice, in KaTrain's own green. A filled disc the size of a
    /// stone, so it reads as "play here" rather than as an annotation.
    public static let bestMove = Color(red: 0.247, green: 0.725, blue: 0.314)

    /// The best move inside the zone of the fight. A blue far from KaTrain's green,
    /// so the two proposals are never mistaken for each other.
    public static let localMove = Color(red: 0.255, green: 0.553, blue: 0.894)

    /// Marks the last move by contrast with the stone it sits on, rather than with a
    /// colour of its own.
    public static func lastMoveMarker(on stone: PlayerColor) -> Color {
        stone == .black ? whiteStone : blackStone
    }

    public static func name(_ color: PlayerColor) -> String {
        color == .black ? "Noir" : "Blanc"
    }
}
