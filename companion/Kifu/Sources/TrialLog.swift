import Foundation
import ImageIO
import UniformTypeIdentifiers
import KifuCore

/// Trial mode: saves raw frames with what the recorder made of them under Documents/Essai/<game>,
/// at the start, on each accepted move or take-back, on each alert and every 10 s, so that a real
/// game can be replayed on a Mac and turned into fixtures. Lives on the session's worker queue.
final class TrialLog: @unchecked Sendable {
    static let defaultsKey = "trialMode"
    static let period: TimeInterval = 10
    /// Periodic frames are skipped while this many images are still being encoded.
    static let maxPending = 2

    enum Reason: String { case start = "debut", move = "coup", takeBack = "retour", alert = "alerte", accepted = "accepte", periodic = "periodique" }

    static var enabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    let directory: URL
    private let encoder = DispatchQueue(label: "Kifu.trial", qos: .utility)
    private var lastSaved: TimeInterval?
    private var index = 0
    private var pending = 0
    private let lock = NSLock()

    init(date: Date) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        directory = GameSession.documents.appendingPathComponent("Essai", isDirectory: true)
            .appendingPathComponent(f.string(from: date), isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func isDue(at time: TimeInterval) -> Bool {
        guard let last = lastSaved else { return true }
        return time - last >= Self.period && pendingCount < Self.maxPending
    }

    /// `reasons` is never empty; the first one names the file.
    func save(frame: GrayImage, time: TimeInterval, reasons: [Reason], calibration: Calibration?, recorder: Recorder) {
        lastSaved = time
        index += 1
        let name = String(format: "%04d-%@", index, reasons[0].rawValue)
        let moves = recorder.record.moves.map(\.move)
        var info: [String: Any] = [
            "reasons": reasons.map(\.rawValue),
            "time": time,
            "lines": calibration?.lines ?? GameSession.lines,
            "stoneHeight": 0,
            "status": "\(recorder.status)",
            "moveCount": moves.count,
            "lastMoves": moves.suffix(3).map(Self.sgf),
            "accepted": Self.rows(recorder.record.position),
            "candidate": Self.rows(recorder.candidate),
            "width": frame.width, "height": frame.height,
        ]
        if let calibration { info["corners"] = calibration.corners.map { [$0.x, $0.y] } }
        if let readings = recorder.lastReadings { info["read"] = Self.rows(readings.position, unreadable: readings.unreadable) }
        let dir = directory
        adjustPending(+1)
        encoder.async {
            if let cg = CalibrationDump.cgImage(of: frame),
               let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, nil)
                CGImageDestinationFinalize(dest)
            }
            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: dir.appendingPathComponent("\(name).json"))
            }
            self.adjustPending(-1)
        }
    }

    private var pendingCount: Int { lock.withLock { pending } }
    private func adjustPending(_ delta: Int) { lock.withLock { pending += delta } }

    /// Fixture rows: `.` empty, `X` black, `O` white, `?` unreadable.
    static func rows(_ p: Position, unreadable: Set<Intersection> = []) -> [String] {
        (0..<p.size).map { row in
            String((0..<p.size).map { col -> Character in
                let i = Intersection(col: col, row: row)
                if unreadable.contains(i) { return "?" }
                switch p[i] { case .black: return "X"; case .white: return "O"; case .empty: return "." }
            })
        }
    }

    static func sgf(_ m: Move) -> String {
        let color = m.color == .black ? "B" : "W"
        return "\(color)[\(m.point.map(SGFWriter.letters) ?? "")]"
    }
}
