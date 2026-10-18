import Foundation

/// The line sent to Moyo on the Mac, in the format GoBoardVision already speaks:
/// `{"size":19,"rows":["X..", ...],"status":"locked"}` and a newline, row 0 at the top.
/// Only the accepted position is sent: what the rules explained, never a raw reading.
/// Two fields go beyond GoBoardVision: `follow` asks Moyo to show this board whatever
/// game it had open, rather than read it as moves against its AI, and `next` ("B" or "W")
/// says whose turn it is, which a position alone cannot tell.
/// The format is specified in docs/protocol.md at the root of the repository.
public enum BoardBroadcast {
    public static let serviceType = "_goboard._tcp"

    /// Whose seat the Mac shows the board from. The phone stands on a third side of the table,
    /// so the players sit at the left and right edges of the image, a quarter turn away.
    public enum Viewpoint: String, Sendable, CaseIterable {
        case leftPlayer, rightPlayer

        /// The position as that player sees it, their own edge at the bottom.
        /// The image's left edge (column 0) is the left player's; the phone's edge (last row)
        /// ends up on their right and on the right player's left.
        public func orient(_ position: Position) -> Position {
            let last = position.size - 1
            var out = Position(size: position.size)
            for i in position.all {
                let source: Intersection
                switch self {
                case .leftPlayer: source = Intersection(col: last - i.row, row: i.col)
                case .rightPlayer: source = Intersection(col: i.row, row: last - i.col)
                }
                out[i] = position[source]
            }
            return out
        }
    }

    public static func line(position: Position, status: Recorder.Status, toPlay: Stone, viewpoint: Viewpoint) -> Data {
        let rows = viewpoint.orient(position).description.split(separator: "\n").map(String.init)
        let payload: [String: Any] = [
            "size": position.size, "rows": rows, "status": statusName(status),
            "follow": true, "next": toPlay == .white ? "W" : "B",
        ]
        var data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// "locked" when the board matches the record, "uncertain" while the referee waits.
    public static func statusName(_ status: Recorder.Status) -> String {
        status == .inSync ? "locked" : "uncertain"
    }
}
