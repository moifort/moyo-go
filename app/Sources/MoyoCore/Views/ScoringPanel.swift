import SwiftUI

/// The count, shown once both players have passed.
///
/// Laid out as a table because the reader needs to check that the totals add up, and
/// a row per component is the only way to make that possible at a glance. Every
/// number comes from the bridge, recomputed after each change — the panel adds
/// nothing up on its own.
public struct ScoringPanel: View {
    public let detail: ScoringDetail
    /// The colour the person played, so the columns say "vous" and "KataGo".
    public let humanColor: PlayerColor?
    public let onNewGame: () -> Void

    public init(detail: ScoringDetail, humanColor: PlayerColor? = nil, onNewGame: @escaping () -> Void) {
        self.detail = detail
        self.humanColor = humanColor
        self.onNewGame = onNewGame
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            PlayerTable(rows: rows, humanColor: humanColor)
            outcome
            Spacer(minLength: 0)
            Button("Nouvelle partie", action: onNewGame)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Comptage")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.primaryText)
            Text("Cliquez un groupe pour le marquer mort ou vivant.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rows: [PlayerTable.Row] {
        var rows: [PlayerTable.Row] = [
            PlayerTable.Row(
                "Territoire",
                black: detail.territory(for: .black),
                white: detail.territory(for: .white)
            )
        ]
        if detail.prisoners != nil {
            rows.append(
                PlayerTable.Row(
                    "Captures",
                    black: detail.prisoners(for: .black),
                    white: detail.prisoners(for: .white)
                )
            )
        }
        if detail.stones != nil {
            rows.append(
                PlayerTable.Row("Pierres", black: detail.stones(for: .black), white: detail.stones(for: .white))
            )
        }
        rows.append(PlayerTable.Row("Komi", black: nil, white: detail.komi))
        rows.append(
            PlayerTable.Row(
                "Total",
                black: detail.total(for: .black),
                white: detail.total(for: .white),
                isTotal: true
            )
        )
        return rows
    }

    private var outcome: some View {
        Group {
            if let outcome = detail.outcome {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.stone(outcome.winner))
                        .frame(width: 11, height: 11)
                    // Short form: the stone already says who won, the figure says
                    // by how much. A sentence would wrap in this width.
                    Text("\(Theme.name(outcome.winner)) +\(PlayerTable.format(outcome.margin))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            } else {
                Text("Partie nulle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
            }
        }
    }
}
