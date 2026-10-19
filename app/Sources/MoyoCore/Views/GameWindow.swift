import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct GameWindow: View {
    @Bindable public var session: GameSession
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isShowingNewGame = false
    @State private var isTargetedByDrop = false
    @State private var exportFailure: String?

    public init(session: GameSession) {
        self.session = session
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(session: session)
                .navigationSplitViewColumnWidth(240)
        } detail: {
            board
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            if columnVisibility == .detailOnly {
                ToolbarItem(placement: .primaryAction) { compactStatus }
            }
        }
        .sheet(isPresented: $isShowingNewGame) {
            NewGameSheet(session: session)
        }
        .focusedSceneValue(\.gameSession, session)
        .onReceive(NotificationCenter.default.publisher(for: .moyoNewGameRequested)) { _ in
            isShowingNewGame = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .moyoOpenRecordRequested)) { _ in
            presentOpenPanel()
        }
        // `lastErrorMessage` was already being set and shown nowhere. A record that
        // will not open has to say so, or the window simply ignores the file.
        .alert(
            "Cette partie n'a pas pu être ouverte",
            isPresented: Binding(
                get: { session.lastErrorMessage != nil },
                set: { if !$0 { session.clearError() } }
            )
        ) {
            Button("Fermer", role: .cancel) { session.clearError() }
        } message: {
            Text(session.lastErrorMessage ?? "")
        }
        .onChange(of: session.pendingExport) { _, document in
            guard let document else { return }
            // Out of the view update: a modal panel run from inside one stalls it.
            Task { @MainActor in presentSavePanel(for: document) }
        }
        .alert(
            "Cette partie n'a pas pu être enregistrée",
            isPresented: Binding(
                get: { exportFailure != nil },
                set: { if !$0 { exportFailure = nil } }
            )
        ) {
            Button("Fermer", role: .cancel) { exportFailure = nil }
        } message: {
            Text(exportFailure ?? "")
        }
    }

    /// The save panel is what grants a sandboxed app the right to write there. The
    /// file is written straight away, while that grant is live.
    private func presentSavePanel(for document: SGFExport.Document) {
        defer { session.exportHandled() }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.moyoSGF]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = document.name
        panel.prompt = "Enregistrer"
        panel.message = "La partie est enregistrée au format SGF, lisible par KaTrain, Sabaki ou OGS."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SGFExport.write(document.contents, to: url)
            session.recordSaved(to: url)
        } catch {
            exportFailure = error.localizedDescription
        }
    }

    /// The open panel is what grants a sandboxed app access to the file. The record
    /// is read straight away, while that grant is live.
    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.moyoSGF]
        panel.prompt = "Ouvrir"
        panel.message = "Choisissez une partie au format SGF."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        session.openRecord(at: url)
    }

    private var board: some View {
        ZStack {
            Theme.windowBackground.ignoresSafeArea()
            if let state = session.state {
                BoardView(
                    state: state,
                    isInteractive: isBoardInteractive(state),
                    onPlay: { point in
                        if state.status == .scoring {
                            session.toggleDead(row: point.row, col: point.col)
                        } else {
                            session.play(row: point.row, col: point.col)
                        }
                    },
                    onDrawZone: state.isReviewing ? { session.drawLocalZone($0) } : nil,
                    showsLocal: session.showsLocalReading
                )
                .padding(20)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == SGFImport.fileExtension })
            else { return false }
            session.openRecord(at: url)
            return true
        } isTargeted: { isTargetedByDrop = $0 }
        .overlay {
            if isTargetedByDrop {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.bestMove.opacity(0.8), lineWidth: 2)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }

    /// While counting, clicks mark groups rather than play stones. A record under
    /// review takes none: `canAct` is already false there, and there is nothing to
    /// count, so both branches land on nothing.
    private func isBoardInteractive(_ state: GameState) -> Bool {
        state.status == .scoring ? true : session.canAct
    }

    private var title: String {
        if session.isReviewing { return session.recordName ?? "Partie" }
        if session.state?.isFollowing == true { return "Partie suivie" }
        return session.state?.status == .finished ? "Partie terminée" : "Partie contre KataGo"
    }

    private var subtitle: String {
        guard let state = session.state else { return "" }
        if state.isReviewing {
            let size = "\(state.size)×\(state.size)"
            guard let result = state.gameInfo?.result else { return size }
            return "\(size) · \(result)"
        }
        if state.status == .finished { return state.result ?? "" }
        return "\(state.size)×\(state.size)"
    }

    /// What remains visible once the sidebar is collapsed: the turn, the score, and a
    /// reduced chart. Nothing disappears, it only condenses.
    private var compactStatus: some View {
        HStack(spacing: 8) {
            if let state = session.state {
                TurnIndicator(color: state.toPlay, isThinking: session.thinking.isVisible, diameter: 13)
                if let lead = session.currentLead, abs(lead) >= 0.05 {
                    // No arrow: the colour already says which way it goes.
                    Text(ScoreChart.label(for: lead))
                        .font(.system(size: 13))
                        .foregroundStyle(lead > 0 ? Theme.chartAhead : Theme.chartBehind)
                        .monospacedDigit()
                }
                ScoreChart(scores: session.scoresFromPlayerSide, moveNumber: state.moveNumber, height: 22)
                    .frame(width: 76)
            }
        }
        // The capsule's own inset is tight on the left; the stone needs room to
        // breathe against its rounded edge.
        .padding(.leading, 6)
    }
}

extension UTType {
    /// macOS declares no type for a go record, so the app imports one of its own.
    ///
    /// Resolved rather than declared: `UTType(importedAs:)` traps outright when the
    /// type is not in the Info.plist, which is exactly the case for a `swift run`
    /// build. Each fallback is a wider net than the last, and the last always exists.
    static let moyoSGF: UTType =
        UTType("org.smart-game-format.sgf")
        ?? UTType(filenameExtension: SGFImport.fileExtension)
        ?? .plainText
}
