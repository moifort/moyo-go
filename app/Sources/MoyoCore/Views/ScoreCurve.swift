import CoreGraphics

/// The geometry of the score curve: which moves it passes through, how wide the
/// game is, how tall a lead is.
///
/// One point per analysed move. A move without an analysis is simply absent: a
/// hole drawn at zero would read as a sudden equality. The chart bridges a hole
/// with a faint dotted line rather than a solid one, so a game whose engine is
/// still catching up does not show a confident diagonal across moves nobody has
/// looked at yet.
public enum ScoreCurve {
    public struct Point: Equatable, Sendable {
        public let move: Int
        public let value: Double

        public init(move: Int, value: Double) {
            self.move = move
            self.value = value
        }
    }

    /// Moves the width of the chart covers at the very least, so the first few
    /// moves do not stretch across the whole chart and then shrink move by move.
    public static let minimumSpan = 60

    /// Half-height of the chart in score points, so small swings stay legible while
    /// a blowout still fits.
    ///
    /// The floor is deliberately low: openings are decided by fractions of a point,
    /// and a floor of five would flatten the first thirty moves into a straight line.
    public static let minimumScale: Double = 2.5

    /// The analysed moves up to the current one, in order.
    public static func points(scores: [Int: Double], upTo moveNumber: Int) -> [Point] {
        scores.keys
            .filter { $0 >= 0 && $0 <= moveNumber }
            .sorted()
            .compactMap { move in scores[move].map { Point(move: move, value: $0) } }
    }

    /// The points cut into runs of consecutive moves: each run is drawn solid, the
    /// holes between them are only bridged.
    public static func runs(_ points: [Point]) -> [[Point]] {
        var runs: [[Point]] = []
        for point in points {
            if let previous = runs.last?.last, point.move == previous.move + 1 {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }
        return runs
    }

    /// Moves the chart spans: the whole record under review, the game so far
    /// while playing, and never less than the minimum.
    public static func span(moveNumber: Int, moveCount: Int?) -> Int {
        max(minimumSpan, moveNumber, moveCount ?? 0)
    }

    public static func scale(for points: [Point]) -> Double {
        let peak = points.map { abs($0.value) }.max() ?? 0
        return max(minimumScale, peak)
    }

    public static func x(move: Int, span: Int, width: CGFloat) -> CGFloat {
        guard span > 0 else { return 0 }
        return CGFloat(move) / CGFloat(span) * width
    }

    /// The midline is halfway down; a lead rises above it, a deficit sinks below.
    ///
    /// The peak stops `inset` short of the edge: drawn right on it, half the stroke
    /// and the current-move dot would be cut off.
    public static func y(value: Double, scale: Double, height: CGFloat, inset: CGFloat = 0) -> CGFloat {
        let half = height / 2
        let magnitude = CGFloat(min(1, abs(value) / scale)) * max(0, half - inset)
        return value >= 0 ? half - magnitude : half + magnitude
    }
}
