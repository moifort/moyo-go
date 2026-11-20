import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct RootView: View {
    /// Owned by the app, not by this view: SwiftUI takes the view down and puts it
    /// back up when the Finder hands over a record, and the engine must outlive that.
    @Bindable public var session: GameSession
    @State private var isShowingNewGame = false
    @State private var exportFailure: String?

    public init(session: GameSession) {
        self.session = session
    }

    public var body: some View {
        Group {
            switch session.phase {
            case .starting, .running:
                // The library shows while KataGo starts: the games kept are there to
                // be looked at, the buttons that need the engine wait for it.
                if session.isShowingLibrary {
                    LibraryView(session: session)
                } else {
                    GameWindow(session: session)
                }
            case .failed(let failure):
                self.failure(failure)
            }
        }
        .preferredColorScheme(.dark)
        .focusedSceneValue(\.gameSession, session)
        .task {
            // A no-op past the first time: the view may come and go, the engine stays.
            session.start()
            RecordOpeningDelegate.beforeQuitting = { [session] done in session.prepareToQuit(done) }
            // A record the app was launched with may have landed before this view.
            if let url = RecordInbox.take() { session.openRecord(at: url) }
            if DemoScript.isRequested() { await DemoScript.run(on: session) }
            if let scene = ScreenshotScene.requested() { await ScreenshotScene.run(scene, on: session) }
        }
        // Here rather than in the game window, which only exists once KataGo is up:
        // the session holds the record until then.
        .onReceive(NotificationCenter.default.publisher(for: .moyoRecordArrived)) { _ in
            if let url = RecordInbox.take() { session.openRecord(at: url) }
        }
        // Here rather than in one view, so the menus answer from the library and
        // from a game alike.
        .sheet(isPresented: $isShowingNewGame) {
            NewGameSheet(session: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .moyoNewGameRequested)) { _ in
            if session.phase == .running { isShowingNewGame = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .moyoOpenRecordRequested)) { _ in
            presentOpenPanel()
        }
        .confirmationDialog(
            "Abandonner la partie ?",
            isPresented: $session.isConfirmingResignation,
            titleVisibility: .visible
        ) {
            Button("Abandonner", role: .destructive) { session.resign() }
            Button("Continuer", role: .cancel) {}
        }
        // Under a title that says what failed: a record that will not open, an
        // analysis that could not be written back, an action refused, the engine.
        .alert(
            session.lastError?.title ?? "",
            isPresented: Binding(
                get: { session.lastError != nil },
                set: { if !$0 { session.clearError() } }
            )
        ) {
            Button("Fermer", role: .cancel) { session.clearError() }
        } message: {
            Text(session.lastError?.message ?? "")
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

    private func failure(_ failure: GameSession.EngineFailure) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Theme.secondaryText)
            Text(failure.title)
                .font(.system(size: 16, weight: .medium))
            Text(failure.detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button("Relancer le moteur") { session.restartEngine() }
                    .buttonStyle(.glassProminent)
                if let log = session.logURL {
                    Button("Afficher le journal") { NSWorkspace.shared.activateFileViewerSelecting([log]) }
                        .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
    }
}
