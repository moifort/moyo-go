import SwiftUI

/// The score curve: a line around a midline, with the area between them filled.
///
/// Read from the human player's side: above the middle they are ahead and the area
/// is white, below it they are behind and it turns red. The midline is drawn, so
/// an even game reads as a flat line on it rather than as an empty chart. Under
/// review the part of the game not yet reached is dimmed, and a hairline marks
/// the position on screen — the way lichess marks the move being looked at.
public struct ScoreChart: View {
    public let scores: [Int: Double]
    public let moveNumber: Int
    /// Moves in the record under review, nil while a game is being played.
    public let moveCount: Int?
    public let height: CGFloat

    public init(
        scores: [Int: Double],
        moveNumber: Int,
        moveCount: Int? = nil,
        height: CGFloat = 56
    ) {
        self.scores = scores
        self.moveNumber = moveNumber
        self.moveCount = moveCount
        self.height = height
    }

    private var lineWidth: CGFloat { height < 30 ? 1 : 1.5 }

    /// Room left above the highest lead and below the deepest deficit, wide enough
    /// for the current-move dot.
    private var inset: CGFloat { height < 30 ? lineWidth / 2 : 3 }

    public var body: some View {
        Canvas { context, size in
            let span = ScoreCurve.span(moveNumber: moveNumber, moveCount: moveCount)
            // Under review the whole record is drawn, so the scale does not jump as
            // the position moves through it.
            let allPoints = ScoreCurve.points(scores: scores, upTo: moveCount ?? moveNumber)
            let scale = ScoreCurve.scale(for: allPoints)
            let half = size.height / 2
            let currentX = ScoreCurve.x(move: moveNumber, span: span, width: size.width)

            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: half)); $0.addLine(to: CGPoint(x: size.width, y: half)) },
                with: .color(Theme.chartMidline),
                lineWidth: 0.5
            )

            let position = { (point: ScoreCurve.Point) in
                CGPoint(
                    x: ScoreCurve.x(move: point.move, span: span, width: size.width),
                    y: ScoreCurve.y(value: point.value, scale: scale, height: size.height, inset: inset)
                )
            }
            // Analysed moves are drawn solid and filled; a hole between them, still
            // being computed, is only bridged by a faint dotted line.
            var line = Path()
            var area = Path()
            var bridges = Path()
            var previous: ScoreCurve.Point?
            for run in ScoreCurve.runs(allPoints) {
                guard let first = run.first, let last = run.last else { continue }
                if let previous {
                    bridges.move(to: position(previous))
                    bridges.addLine(to: position(first))
                }
                previous = last
                var segment = Path()
                segment.move(to: position(first))
                for point in run.dropFirst() { segment.addLine(to: position(point)) }
                line.addPath(segment)
                segment.addLine(to: CGPoint(x: position(last).x, y: half))
                segment.addLine(to: CGPoint(x: position(first).x, y: half))
                segment.closeSubpath()
                area.addPath(segment)
            }

            let above = CGRect(x: 0, y: 0, width: size.width, height: half)
            let below = CGRect(x: 0, y: half, width: size.width, height: half)
            // What lies past the position on screen is still the game, only not yet
            // reached: drawn, but faded.
            let reached = CGRect(x: 0, y: 0, width: currentX, height: size.height)
            let ahead = CGRect(x: currentX, y: 0, width: size.width - currentX, height: size.height)

            // Each half is painted through a mask rather than by intersecting paths:
            // a boolean operation treats the open line as a shape and closes it,
            // which strokes a straight segment from its first point to its last.
            for (region, dim) in [(reached, false), (ahead, true)] where region.width > 0 {
                for (half, fill, colour) in [
                    (above, Theme.chartAheadFill, Theme.chartAhead),
                    (below, Theme.chartBehindFill, Theme.chartBehind),
                ] {
                    var layer = context
                    layer.clip(to: Path(region))
                    layer.clip(to: Path(half))
                    layer.opacity = dim ? 0.3 : 1
                    layer.fill(area, with: .color(fill))
                    layer.stroke(line, with: .color(colour), style: stroke)
                    layer.stroke(bridges, with: .color(colour.opacity(0.5)), style: bridgeStroke)
                }
            }

            if let moveCount, moveNumber < moveCount {
                context.stroke(
                    Path { $0.move(to: CGPoint(x: currentX, y: 0)); $0.addLine(to: CGPoint(x: currentX, y: size.height)) },
                    with: .color(Theme.primaryText.opacity(0.5)),
                    lineWidth: 1
                )
            }

            // The point at the position on screen, so the eye finds the current
            // value without hunting for the end of the line.
            if let current = allPoints.last(where: { $0.move <= moveNumber }), height >= 30 {
                let centre = position(current)
                let dot = CGRect(x: centre.x - 2.5, y: centre.y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(current.value >= 0 ? Theme.chartAhead : Theme.chartBehind))
            }
        }
        .frame(height: height)
        .accessibilityLabel("Graphe de l'avantage au score")
    }

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    private var bridgeStroke: StrokeStyle {
        StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3])
    }

    /// The bare magnitude, with a French decimal comma. No sign: the colour already
    /// says which way it goes — white ahead, red behind.
    public static func label(for value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded) < 0.05 { return "0" }
        return String(format: "%.1f", abs(rounded)).replacingOccurrences(of: ".", with: ",")
    }

    /// The same figure with its sign, for the readout above the chart, where it is
    /// read on its own. A true minus sign, not a hyphen.
    public static func signedLabel(for value: Double) -> String {
        let bare = label(for: value)
        if bare == "0" { return bare }
        return (value > 0 ? "+" : "−") + bare
    }
}
