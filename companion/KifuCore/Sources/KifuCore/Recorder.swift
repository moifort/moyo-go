import Foundation

/// Anything that turns an image into readings. The app uses IntersectionReader; tests script it.
public protocol BoardReader {
    func read(_ image: GrayImage, previous: Position?) -> Readings
}

extension IntersectionReader: BoardReader {}

public struct RecorderSettings: Sendable, Equatable {
    /// Identical consecutive readings before a change is considered.
    public var requiredFrames = 3
    /// Seconds a stable, unexplained position may last before the referee asks for help.
    public var lostAfter: TimeInterval = 8
    public init() {}
}

/// The referee: reads images, keeps only what the rules explain, and writes the record.
public struct Recorder {
    public enum Status: Sendable, Equatable {
        /// The board matches the record.
        case inSync
        /// The board shows a stable change the rules do not explain yet.
        case pending
        /// A legal move was seen whose captured stones are still on the board.
        case awaitingCaptureRemoval
        /// The pending change lasted too long: the user is asked to arbitrate.
        case lost
    }

    public struct Update: Sendable, Equatable {
        public var moves: [Move] = []
        public var takenBack = 0
        public var status: Status = .inSync
        public init() {}
    }

    public private(set) var record: GameRecord
    public private(set) var candidate: Position
    public private(set) var status: Status = .inSync
    /// What the last image showed, before the stability filter.
    public private(set) var lastReadings: Readings?
    public let settings: RecorderSettings
    private var reader: BoardReader
    private var filter: StabilityFilter
    private var pendingSince: TimeInterval?
    private var pendingPosition: Position?

    public init(reader: BoardReader, start: Position, date: Date = Date(), settings: RecorderSettings = RecorderSettings()) {
        self.reader = reader
        self.settings = settings
        record = GameRecord(start: start, date: date)
        candidate = start
        filter = StabilityFilter(start: start, required: settings.requiredFrames)
    }

    /// Feeds one image taken at `time` (seconds, any monotonic origin).
    public mutating func process(_ image: GrayImage, at time: TimeInterval) -> Update {
        var update = Update()
        let readings = reader.read(image, previous: candidate)
        lastReadings = readings
        candidate = filter.push(readings)
        let accepted = record.position

        if candidate == accepted {
            clearPending()
        } else if let explained = Rules.explanation(from: accepted, to: candidate, toPlay: record.toPlay) {
            record.apply(explained.moves, uncertain: explained.guessedOrder)
            update.moves = explained.moves
            clearPending()
        } else if record.takeBack(to: candidate) {
            update.takenBack = accepted.stones.count - candidate.stones.count
            clearPending()
        } else if Rules.isAwaitingCaptureRemoval(from: accepted, to: candidate, toPlay: record.toPlay) {
            status = .awaitingCaptureRemoval
            pendingSince = nil; pendingPosition = nil
        } else {
            if pendingPosition != candidate {
                pendingPosition = candidate
                pendingSince = time
            }
            if status != .lost {
                status = time - (pendingSince ?? time) >= settings.lostAfter ? .lost : .pending
            }
        }
        update.status = status
        return update
    }

    /// "C'est bon": the board as seen becomes the record.
    public mutating func accept() {
        record.force(to: candidate)
        clearPending()
    }

    /// New calibration, same game.
    public mutating func recalibrate(reader: BoardReader) {
        self.reader = reader
        candidate = record.position
        filter.reset(to: record.position)
        clearPending()
    }

    private mutating func clearPending() {
        status = .inSync
        pendingSince = nil
        pendingPosition = nil
    }
}
