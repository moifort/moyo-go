import SwiftUI

/// The lead written out, then the curve that led to it.
///
/// The figure says how much, the caption says who, the curve says since when. On
/// its own the curve was a riddle; with the sentence above it, it is a story.
public struct ScoreSection: View {
    public let scores: [Int: Double]
    public let moveNumber: Int
    public let moveCount: Int?
    /// The player's lead, from their side. Nil while nothing has been analysed.
    public let lead: Double?
    /// Who is ahead, in words: "Vous menez", "Blanc mène".
    public let caption: (Double) -> String
    /// Goes to the move clicked on the chart, under review.
    public let onSelect: ((Int) -> Void)?

    public init(
        scores: [Int: Double],
        moveNumber: Int,
        moveCount: Int? = nil,
        lead: Double?,
        caption: @escaping (Double) -> String,
        onSelect: ((Int) -> Void)? = nil
    ) {
        self.scores = scores
        self.moveNumber = moveNumber
        self.moveCount = moveCount
        self.lead = lead
        self.caption = caption
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Score")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lead.map(ScoreChart.signedLabel) ?? "—")
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(colour)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.3), value: lead)
                Text(lead.map(caption) ?? "En attente de l'analyse")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            ScoreChart(scores: scores, moveNumber: moveNumber, moveCount: moveCount, onSelect: onSelect)
        }
    }

    private var colour: Color {
        guard let lead, abs(lead) >= 0.05 else { return Theme.primaryText }
        return lead > 0 ? Theme.chartAhead : Theme.chartBehind
    }
}

/// A section's name, small and spaced the way the Settings app names its groups:
/// read once, then ignored.
struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}
