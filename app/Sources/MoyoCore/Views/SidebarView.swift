import SwiftUI

public struct SidebarView: View {
    @Bindable public var session: GameSession
    @State private var isConfirmingResignation = false

    public init(session: GameSession) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let state = session.state, state.isReviewing {
                ReviewPanel(session: session, state: state)
            } else if let state = session.state, let scoring = state.scoring {
                ScoringPanel(detail: scoring) {
                    NotificationCenter.default.post(name: .moyoNewGameRequested, object: nil)
                }
            } else if let state = session.state {
                if let winner = state.winnerByResignation {
                    resignationRow(winner)
                } else {
                    turnRow(state)
                }
                divider
                scoreSection(state)
                divider
                PlayerTable(rows: playingRows(state))
                divider
                opponentSection
                divider
                phoneSection
                Spacer(minLength: 0)
                if state.status == .finished {
                    // Nothing left to play: the only way on is the next game.
                    Button("Nouvelle partie") {
                        NotificationCenter.default.post(name: .moyoNewGameRequested, object: nil)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                } else {
                    actions(state)
                }
            } else {
                Text("Préparation de la partie…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.sidebarVeil)
        .help(session.engineDescription ?? "")
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }

    private func turnRow(_ state: GameState) -> some View {
        HStack(spacing: 8) {
            TurnIndicator(color: state.toPlay, isThinking: session.thinking.isVisible)
            Text(Theme.name(state.toPlay))
                .font(.system(size: 14))
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
    }

    /// Takes the place of the turn once a player has given up: the stone says who
    /// won, the words say how.
    private func resignationRow(_ winner: PlayerColor) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.stone(winner))
                .frame(width: 13, height: 13)
            Text("\(Theme.name(winner)) gagne par abandon")
                .font(.system(size: 14))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// The chart carries its own figure, written small at the tip of the last bar,
    /// so there is no separate readout.
    private func scoreSection(_ state: GameState) -> some View {
        ScoreChart(
            scores: session.scoresFromPlayerSide,
            moveNumber: state.moveNumber,
            annotation: session.currentLead
        )
    }

    /// What is already known per player while the game is on. Territory only exists
    /// once the dead stones are agreed, so it appears at the count, not before.
    private func playingRows(_ state: GameState) -> [PlayerTable.Row] {
        [
            PlayerTable.Row(
                "Captures",
                black: state.captures.byBlack,
                white: state.captures.byWhite
            ),
            PlayerTable.Row("Komi", black: nil, white: session.settings.komi),
        ]
    }

    /// The opponent, and the way to change it: the line that shows the mode is the
    /// line that switches it. Its setting belongs to the new-game sheet, not here —
    /// the sidebar states who you are playing, it is not a control panel.
    private var opponentSection: some View {
        Menu {
            ForEach(session.modes) { mode in
                Button {
                    session.setAI(mode: mode, value: session.settingValue(for: mode))
                } label: {
                    Text(mode.name)
                    if mode.id == session.currentMode.id { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Text(session.currentMode.name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.primaryText.opacity(0.85))
                .lineLimit(1)
        }
        // The borderless style draws its own indicator; adding one put a second
        // chevron ahead of the label.
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(session.currentMode.summary)
    }

    /// The phone that watches the real board. One line: the button to connect it,
    /// or what it is doing once connected.
    private var phoneSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .foregroundStyle(Theme.secondaryText)
            switch session.phone.status {
            case .idle:
                Button("Connecter le téléphone") { session.phone.connect() }
                    .buttonStyle(.link)
                    .font(.system(size: 13))
            case .searching:
                Text("Recherche du téléphone…").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                Button("Arrêter") { session.phone.disconnect() }.buttonStyle(.link).font(.system(size: 12))
            case .connecting(let name):
                Text("Connexion à \(name)…").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            case .connected(let name):
                Text(name).font(.system(size: 13)).foregroundStyle(Theme.primaryText).lineLimit(1)
                Button("Déconnecter") { session.phone.disconnect() }.buttonStyle(.link).font(.system(size: 12))
            case .failed(let message):
                Text("Échec : \(message)").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                Button("Réessayer") { session.phone.connect() }.buttonStyle(.link).font(.system(size: 12))
            }
            Spacer(minLength: 0)
        }
    }

    private func actions(_ state: GameState) -> some View {
        VStack(spacing: 7) {
            Button {
                session.undo()
            } label: {
                Label("Annuler", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!session.canAct)

            Button {
                session.passTurn()
            } label: {
                Label("Passer", systemImage: "forward.end")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!session.canAct)

            // Available even while the AI is thinking — you give up when you decide
            // to, not when it is your turn. Confirmed because it ends the game.
            Button(role: .destructive) {
                isConfirmingResignation = true
            } label: {
                Label("Abandonner", systemImage: "flag")
                    .frame(maxWidth: .infinity)
            }
            .disabled(state.status != .playing)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .confirmationDialog(
            "Abandonner la partie ?",
            isPresented: $isConfirmingResignation,
            titleVisibility: .visible
        ) {
            Button("Abandonner", role: .destructive) { session.resign() }
            Button("Continuer", role: .cancel) {}
        }
    }
}

/// What the sidebar shows while a record is being read.
///
/// A review has no turn to announce and no action to offer: what it has is a
/// position in a record, the two players, and an engine still catching up. The chart
/// covers the whole game from the start, since every move of it already exists.
struct ReviewPanel: View {
    @Bindable var session: GameSession
    let state: GameState

    /// The name of the button under the pointer, said above the buttons at once.
    @State private var hoveredStep: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            divider
            ScoreChart(
                scores: session.scoresFromPlayerSide,
                moveNumber: state.moveNumber,
                annotation: session.currentLead
            )
            if let progress = session.analysisProgress {
                gauge(done: progress.done, total: progress.total)
            }
            divider
            players
            PlayerTable(rows: rows)
            Spacer(minLength: 0)
            footer
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Coup \(state.moveNumber)")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                if let count = state.moveCount {
                    Text("sur \(count)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            if let depth = state.variationDepth, depth > 0 {
                let local = state.variationKind == .local
                Text("\(local ? "Séquence locale" : "Proposition de KataGo"), \(depth) coup\(depth > 1 ? "s" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(local ? Theme.localMove : Theme.bestMove)
            } else if let event = state.gameInfo?.event {
                Text(event)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    /// The engine is still working: say so plainly and say how far it has got.
    ///
    /// The chart filling in underneath is the real feedback; this line only exists so
    /// a board without a marker reads as "not yet" rather than as "nothing to say".
    private func gauge(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Analyse \(done) / \(total)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
        }
    }

    /// The two names, on their own lines rather than in the table.
    ///
    /// PlayerTable is built around right-aligned tabular figures; a name dropped into
    /// a number column reads as a mistake. Absent entirely when the record names
    /// neither player, which many do not.
    @ViewBuilder private var players: some View {
        let info = state.gameInfo
        if info?.label(for: .black) != nil || info?.label(for: .white) != nil {
            VStack(alignment: .leading, spacing: 5) {
                name(.black, label: info?.label(for: .black))
                name(.white, label: info?.label(for: .white))
            }
        }
    }

    private func name(_ color: PlayerColor, label: String?) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.stone(color))
                .strokeBorder(Theme.primaryText.opacity(color == .black ? 0.25 : 0), lineWidth: 0.5)
                .frame(width: 10, height: 10)
            Text(label ?? "Joueur inconnu")
                .font(.system(size: 12))
                .foregroundStyle(label == nil ? Theme.secondaryText : Theme.primaryText.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Theme.name(color)) : \(label ?? "inconnu")")
    }

    private var rows: [PlayerTable.Row] {
        [
            PlayerTable.Row(
                "Captures",
                black: state.captures.byBlack,
                white: state.captures.byWhite
            )
        ]
    }

    /// The same moves as the Revue menu and its arrow keys, within reach of the mouse:
    /// a record dropped on the window is read with the pointer as often as with keys.
    private var navigation: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                step("Début de la partie", systemImage: "backward.end.fill", enabled: session.canStepBackward) {
                    session.goto(moveNumber: 0)
                }
                step("Coup précédent", systemImage: "backward.frame.fill", enabled: session.canStepBackward) {
                    session.step(-1)
                }
                step("Coup suivant", systemImage: "forward.frame.fill", enabled: session.canStepForward) {
                    session.step(1)
                }
                step("Fin de la partie", systemImage: "forward.end.fill", enabled: session.canStepForward) {
                    if let count = state.moveCount { session.goto(moveNumber: count) }
                }
            }
            HStack(spacing: 7) {
                step(
                    "Remonter la proposition de KataGo", systemImage: "arrow.uturn.backward",
                    enabled: (state.variationDepth ?? 0) > 0
                ) {
                    session.stepVariation(-1)
                }
                step("Dérouler la proposition de KataGo", systemImage: "sparkles", enabled: true) {
                    session.stepVariation(1)
                }
            }
            HStack(spacing: 7) {
                step(
                    "Remonter la séquence locale", systemImage: "arrow.uturn.backward.circle",
                    enabled: session.isWalkingLocal
                ) {
                    session.stepVariation(-1, kind: .local)
                }
                step("Dérouler la séquence locale", systemImage: "scope", enabled: session.canWalkLocal) {
                    session.stepVariation(1, kind: .local)
                }
                // Drawing has no button: it is a drag across the board, which the line
                // above the buttons teaches while there is nothing to undo.
                step(
                    session.hasDrawnZone
                        ? "Revenir à la zone automatique (Échap)"
                        : "Glissez sur le goban pour tracer la zone du combat",
                    systemImage: "viewfinder", enabled: session.hasDrawnZone
                ) {
                    session.clearDrawnZone()
                }
            }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    /// An icon wide enough to hit, named above the buttons on hover and for
    /// VoiceOver: four labels would not fit across the sidebar. The system tooltip
    /// waits too long, and not at all on a disabled button, to explain an icon.
    private func step(
        _ title: String, systemImage: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(title)
        .disabled(!enabled)
        .onHover { inside in
            if inside {
                hoveredStep = title
            } else if hoveredStep == title {
                hoveredStep = nil
            }
        }
    }

    /// One line kept in place whether or not something is hovered, so the buttons
    /// below never jump.
    private var stepHint: some View {
        Text(hoveredStep ?? " ")
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepHint
            navigation
            Button {
                NotificationCenter.default.post(name: .moyoNewGameRequested, object: nil)
            } label: {
                Label("Nouvelle partie", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }
}
