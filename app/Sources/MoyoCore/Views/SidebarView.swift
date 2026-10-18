import SwiftUI

public struct SidebarView: View {
    @Bindable public var session: GameSession
    @State private var isConfirmingResignation = false
    @State private var isConfiguringAI = false

    public init(session: GameSession) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let state = session.state, state.isReviewing {
                ReviewPanel(session: session, state: state)
            } else if let state = session.state, let scoring = state.scoring {
                ScoringPanel(detail: scoring, humanColor: state.humanColor) {
                    NotificationCenter.default.post(name: .moyoNewGameRequested, object: nil)
                }
            } else if let state = session.state {
                statusRow(state)
                divider
                ScoreSection(
                    scores: session.scoresFromPlayerSide,
                    moveNumber: state.moveNumber,
                    lead: session.currentLead,
                    caption: leadCaption
                )
                divider
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Joueurs")
                    PlayerTable(rows: playingRows(state), humanColor: state.humanColor)
                }
                divider
                opponentSection
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
        .sheet(isPresented: $isConfiguringAI) {
            AISettingsSheet(session: session)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }

    /// Whose move it is, said to the player rather than by colour: the stone
    /// already shows the colour, the words say what it means for them. Once the
    /// game is over the same line says how it ended.
    private func statusRow(_ state: GameState) -> some View {
        HStack(spacing: 10) {
            TurnIndicator(color: state.toPlay, isThinking: session.thinking.isVisible)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle(state))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(statusDetail(state))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func statusTitle(_ state: GameState) -> String {
        if let winner = state.winnerByResignation {
            return "\(Theme.name(winner)) gagne par abandon"
        }
        if state.status == .finished { return "Partie terminée" }
        if session.thinking.isVisible { return "KataGo réfléchit…" }
        return state.isHumanTurn ? "À vous de jouer" : "Au tour de KataGo"
    }

    private func statusDetail(_ state: GameState) -> String {
        if state.status == .finished, let result = state.result, state.winnerByResignation == nil {
            return result
        }
        return "Coup \(state.moveNumber) · \(Theme.name(state.toPlay)) au trait"
    }

    private func leadCaption(_ lead: Double) -> String {
        guard abs(lead) >= 0.05 else { return "Égalité" }
        return lead > 0 ? "Vous menez" : "KataGo mène"
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

    /// Who you are playing, and the board it is played on: the mode by name with
    /// its level as a tag and a gear to change it, then the phone that watches the
    /// real board. The setting itself lives in a sheet — the sidebar states who you
    /// are playing, it is not a control panel.
    private var opponentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Adversaire")
            HStack(spacing: 8) {
                Text(session.currentMode.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .help(session.currentMode.summary)
                if let tag = session.currentMode.tag(for: session.settingValue(for: session.currentMode)) {
                    Tag(tag)
                }
                Spacer(minLength: 0)
                Button {
                    isConfiguringAI = true
                } label: {
                    // A small glyph in a roomier disc: at its natural size the
                    // icon filled the circle edge to edge.
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Configurer l'IA")
                .accessibilityLabel("Configurer l'IA")
            }
            phoneButton
        }
    }

    /// The phone that watches the real board, in the same shape as the buttons at
    /// the foot of the sidebar. The button says where the link stands and does the
    /// one thing that makes sense from there.
    @ViewBuilder private var phoneButton: some View {
        Group {
            switch session.phone.status {
            case .idle:
                Button {
                    session.phone.connect()
                } label: {
                    Label("Connecter", systemImage: "iphone")
                        .frame(maxWidth: .infinity)
                }
                .help("Connecter le téléphone qui filme le plateau")
            case .searching, .connecting:
                Button {
                    session.phone.disconnect()
                } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(phoneProgress).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .help("Arrêter la recherche")
            case .connected(let name):
                Button {
                    session.phone.disconnect()
                } label: {
                    Label {
                        Text("Connecté")
                    } icon: {
                        Image(systemName: "iphone").foregroundStyle(Theme.connected)
                    }
                    .frame(maxWidth: .infinity)
                }
                .help("\(name) — cliquer pour déconnecter")
            case .failed(let message):
                Button {
                    session.phone.connect()
                } label: {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .help("Échec : \(message)")
            }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    private var phoneProgress: String {
        if case .connecting = session.phone.status { return "Connexion…" }
        return "Recherche…"
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

/// A small capsule holding one word about a thing: the opponent's level.
struct Tag: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Theme.primaryText.opacity(0.9))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Theme.tagBackground, in: Capsule())
            .lineLimit(1)
            .fixedSize()
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
            ScoreSection(
                scores: session.scoresFromPlayerSide,
                moveNumber: state.moveNumber,
                moveCount: state.moveCount,
                lead: session.currentLead,
                caption: { leadCaption($0, perspective: state.humanColor) }
            )
            if let progress = session.analysisProgress {
                gauge(done: progress.done, total: progress.total)
            }
            divider
            SectionTitle("Joueurs")
            players
            PlayerTable(rows: rows)
            Spacer(minLength: 0)
            footer
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }

    /// A record has no "you": the lead is named after the colour that holds it.
    private func leadCaption(_ lead: Double, perspective: PlayerColor) -> String {
        guard abs(lead) >= 0.05 else { return "Égalité" }
        return "\(Theme.name(lead > 0 ? perspective : perspective.opponent)) mène"
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
                step(
                    "Dérouler la séquence locale", systemImage: "scope", enabled: session.canWalkLocal,
                    busy: state.isReadingLocally && session.showsLocalReading
                ) {
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
    /// `busy` swaps the icon for a spinner while what the button asks for is still
    /// being worked out; the button stays live, and the bridge keeps the press.
    private func step(
        _ title: String, systemImage: String, enabled: Bool, busy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
            }
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
