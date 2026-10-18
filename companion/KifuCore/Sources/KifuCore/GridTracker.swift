import Foundation

/// Follows the grid during a game. The stand or the board gets nudged, and a grid left where
/// it was calibrated loses the far rows first: twenty pixels there is half a row. The corners
/// are refitted within a few pixels every `period` seconds, so a larger shift is caught up
/// over consecutive refits while a line never gets mistaken for its neighbour.
public struct GridTracker: Sendable, Equatable {
    public static let radius = 8
    /// Corners closer than this to the last ones are not worth a new reader.
    static let minimumMove = 0.25

    public private(set) var calibration: Calibration
    public let period: TimeInterval
    private var lastFit: TimeInterval?

    public init(calibration: Calibration, period: TimeInterval = 2) {
        self.calibration = calibration
        self.period = period
    }

    /// The calibration refitted on `image`, when a refit is due and the corners moved.
    public mutating func update(_ image: GrayImage, at time: TimeInterval) -> Calibration? {
        if let lastFit, time - lastFit < period { return nil }
        lastFit = time
        let corners = BoardGeometry.fitCorners(calibration.corners, lines: calibration.lines, in: image, radius: Self.radius)
        guard zip(corners, calibration.corners).contains(where: { BoardGeometry.distance($0, $1) > Self.minimumMove }) else { return nil }
        calibration = Calibration(lines: calibration.lines, corners: corners)
        return calibration
    }
}
