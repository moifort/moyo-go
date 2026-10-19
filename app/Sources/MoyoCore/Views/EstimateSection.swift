import SwiftUI

/// The score as it would stand if the game ended the way KataGo sees it.
///
/// A settled position gets the same table as the real count, so the two read
/// alike. An open one gets KataGo's lead, to the half point: counting only the
/// points already decided would leave most of the board out. Every figure comes
/// from the bridge.
struct EstimateSection: View {
    let estimate: ScoreEstimate?
    /// The colour the person played, so the columns say "vous"; nil for a record.
    let humanColor: PlayerColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Estimation")
            if let count = estimate?.count {
                PlayerTable(rows: ScoringPanel.rows(for: count), humanColor: humanColor)
                CountOutcome(detail: count)
            } else if let lead = estimate?.lead {
                open(lead: lead)
            } else {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("En attente de l'analyse")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func open(lead: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if lead == 0 {
                    Text("Égalité")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.primaryText)
                } else {
                    let winner: PlayerColor = lead > 0 ? .black : .white
                    Circle()
                        .fill(Theme.stone(winner))
                        .frame(width: 11, height: 11)
                    Text("\(Theme.name(winner)) +\(PlayerTable.format(abs(lead)))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            Text("Partie encore ouverte : sur le goban, ce que KataGo donne déjà à chacun.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shows or hides the estimate. It stays on, move after move, until pressed again.
struct EstimateButton: View {
    @Bindable var session: GameSession

    var body: some View {
        Button {
            session.toggleEstimate()
        } label: {
            Label(
                session.isEstimating ? "Masquer l'estimation" : "Estimer le score",
                systemImage: session.isEstimating ? "eye.slash" : "square.grid.3x3.square"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .disabled(!session.canEstimate && !session.isEstimating)
        .help("Le territoire de chacun selon KataGo, compté comme en fin de partie (⌘E)")
    }
}
