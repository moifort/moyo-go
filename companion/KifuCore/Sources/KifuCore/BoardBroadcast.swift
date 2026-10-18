import Foundation

/// The line sent to Moyo on the Mac, in the format GoBoardVision already speaks:
/// `{"size":19,"rows":["X..", ...],"status":"locked"}` and a newline, row 0 at the top.
/// Only the accepted position is sent: what the rules explained, never a raw reading.
public enum BoardBroadcast {
    public static let serviceType = "_goboard._tcp"

    public static func line(position: Position, status: Recorder.Status) -> Data {
        let rows = position.description.split(separator: "\n").map(String.init)
        let payload: [String: Any] = ["size": position.size, "rows": rows, "status": statusName(status)]
        var data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// "locked" when the board matches the record, "uncertain" while the referee waits.
    public static func statusName(_ status: Recorder.Status) -> String {
        status == .inSync ? "locked" : "uncertain"
    }
}
