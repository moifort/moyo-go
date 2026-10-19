import SwiftUI

public struct SidebarView: View {
    @Bindable public var session: GameSession
    @State private var isConfirmingResignation = false
    @State private var isConfiguringAI = false

    public init(session: GameSession) {
        self.session = session
    }

    /// Scrolls once the panel outgrows the window. Without it the split view
    /// stretched every column to the sidebar's height, and the board, sized on
    /// that height, grew past the window and was cut off. The minimum height keeps
    /// the footer pinned to the bottom whenever everything fits.
    public var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                content
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.sidebarVeil)
        .help(session.engineDescription ?? "")
        .sheet(isPresented: $isConfiguringAI) {
            AISettingsSheet(session: session)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let state = session.state, state.isAnalysing {
                ReviewPanel(session: session, state: state)
            } else if let state = session.state, state.isFollowing {
                followingPanel(state)
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
                if session.isEstimating {
                    EstimateSection(estimate: state.estimate, humanColor: state.humanColor)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Joueurs")
                        PlayerTable(rows: playingRows(state), humanColor: state.humanColor)
                    }
                }
                divider
                opponentSection
                Spacer(minLength: 0)
                // The phone heads the footer: it is how a game on a real board
                // begins, before any of the moves the buttons below act on.
                VStack(spacing: 7) {
                    PhoneButton(session: session)
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

    /// Who you are playing: the mode by name with its level as a tag and a button
    /// to change it. The setting itself lives in a sheet — the sidebar states who you
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
        }
    }

    /// A game played on the real board, followed move by move. Nothing to play
    /// here: the turn, the lead by colour — both players are people — and the phone.
    @ViewBuilder private func followingPanel(_ state: GameState) -> some View {
        HStack(spacing: 10) {
            TurnIndicator(color: state.toPlay, isThinking: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.inSync == false ? "Position non reconnue" : "Partie suivie")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(state.inSync == false ? Theme.warning : Theme.primaryText)
                    .lineLimit(1)
                Text(statusDetail(state))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .help(
            state.inSync == false
                ? "Le plateau vu par le téléphone ne découle d'aucun coup : la partie reprend dès qu'il redevient cohérent."
                : ""
        )
        divider
        if session.followsWithAnalysis {
            ScoreSection(
                scores: session.scoresFromPlayerSide,
                moveNumber: state.moveNumber,
                lead: session.currentLead,
                caption: { lead in
                    guard abs(lead) >= 0.05 else { return "Égalité" }
                    return "\(Theme.name(lead > 0 ? state.humanColor : state.humanColor.opponent)) mène"
                }
            )
            divider
        }
        if session.isEstimating && session.canEstimate {
            EstimateSection(estimate: state.estimate, humanColor: nil)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Joueurs")
                PlayerTable(rows: playingRows(state))
            }
        }
        Spacer(minLength: 0)
        Text("Les coups joués sur le plateau s'affichent ici. La partie se termine sur Kifu.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(3)
        if session.followsWithAnalysis {
            EstimateButton(session: session)
        }
        PhoneButton(session: session)
        Toggle(isOn: $session.followsWithAnalysis) {
            Text("Analyse KataGo")
                .font(.system(size: 12))
                .foregroundStyle(Theme.primaryText)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .help(
            "Le score et sa courbe ; sur le plateau, le meilleur coup en vert et, en bleu, "
                + "le meilleur coup près du dernier joué, avec son coût au survol. Éteinte, KataGo ne calcule rien."
        )
    }

    private func actions(_ state: GameState) -> some View {
        VStack(spacing: 7) {
            EstimateButton(session: session)

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

/// What the sidebar shows in analysis: a record read, or a game set aside to study.
///
/// No turn to announce: both colours are placed by hand. What it has is a position
/// in the tree, the chart of the game, the two players, and an engine still catching
/// up. The chart covers the whole game from the start, since every move of it
/// already exists; the tree below it holds every branch tried.
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
            SectionTitle("Variantes")
            VariationTree(
                layout: session.treeLayout,
                currentID: state.nodeId,
                liveID: state.liveNodeId,
                onSelect: { session.gotoNode($0) },
                canDelete: { session.isDeletable($0) },
                onDelete: { session.deleteBranch($0) }
            )
            divider
            SectionTitle("Joueurs")
            players
            if session.isEstimating {
                EstimateSection(estimate: state.estimate, humanColor: nil)
            } else {
                PlayerTable(rows: rows)
            }
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
            } else if session.isInBranch {
                Text("Variante · \(Theme.name(state.toPlay)) au trait")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.localMove)
            } else if !state.isReviewing, let result = state.result {
                Text(result)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
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

    /// The same moves as the Analyse menu and its keys, within reach of the mouse:
    /// a record dropped on the window is read with the pointer as often as with keys.
    /// Each button names its shortcut on hover, so the keys are learnt by using it.
    private var navigation: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                step("Début de la partie (⌘←)", systemImage: "backward.end.fill", enabled: session.canStepBackward) {
                    session.navigate(.start)
                }
                step("Coup précédent (←)", systemImage: "backward.frame.fill", enabled: session.canStepBackward) {
                    session.step(-1)
                }
                step("Coup suivant (→)", systemImage: "forward.frame.fill", enabled: session.canStepForward) {
                    session.step(1)
                }
                step("Fin de la variante (⌘→)", systemImage: "forward.end.fill", enabled: session.canStepForward) {
                    session.navigate(.end)
                }
            }
            HStack(spacing: 7) {
                step("Variante précédente (↑)", systemImage: "chevron.up", enabled: session.hasPreviousSibling) {
                    session.navigate(.previousSibling)
                }
                step("Variante suivante (↓)", systemImage: "chevron.down", enabled: session.hasNextSibling) {
                    session.navigate(.nextSibling)
                }
                step("Revenir à la partie (⌘↑)", systemImage: "arrow.turn.left.up", enabled: session.isInBranch) {
                    session.navigate(.game)
                }
                step("Passer (⌘P)", systemImage: "hand.raised", enabled: true) {
                    session.passTurn()
                }
            }
            HStack(spacing: 7) {
                step(
                    "Remonter la proposition de KataGo (⇧⌥←)", systemImage: "arrow.uturn.backward",
                    enabled: (state.variationDepth ?? 0) > 0
                ) {
                    session.stepVariation(-1)
                }
                step("Dérouler la proposition de KataGo (⇧⌥→)", systemImage: "sparkles", enabled: true) {
                    session.stepVariation(1)
                }
            }
            HStack(spacing: 7) {
                step(
                    "Remonter la séquence locale (⌥←)", systemImage: "arrow.uturn.backward.circle",
                    enabled: session.isWalkingLocal
                ) {
                    session.stepVariation(-1, kind: .local)
                }
                step(
                    "Dérouler la séquence locale (⌥→)", systemImage: "scope", enabled: session.canWalkLocal,
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
            if session.isFollowing, state.isReviewing {
                Text("La prochaine partie commencée sur Kifu s'affichera ici.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
            }
            stepHint
            navigation
            EstimateButton(session: session)
            PhoneButton(session: session)
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
