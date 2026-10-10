import SwiftUI

public struct RootView: View {
    /// Owned by the app, not by this view: SwiftUI takes the view down and puts it
    /// back up when the Finder hands over a record, and the engine must outlive that.
    @Bindable public var session: GameSession

    public init(session: GameSession) {
        self.session = session
    }

    public var body: some View {
        Group {
            switch session.phase {
            case .starting:
                startup
            case .running:
                GameWindow(session: session)
            case .failed(let message):
                failure(message)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // A no-op past the first time: the view may come and go, the engine stays.
            session.start()
            // A record the app was launched with may have landed before this view.
            if let url = RecordInbox.take() { session.openRecord(at: url) }
            if DemoScript.isRequested() { await DemoScript.run(on: session) }
        }
        // Here rather than in the game window, which only exists once KataGo is up:
        // the session holds the record until then.
        .onReceive(NotificationCenter.default.publisher(for: .moyoRecordArrived)) { _ in
            if let url = RecordInbox.take() { session.openRecord(at: url) }
        }
    }

    private var startup: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Démarrage de KataGo…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Theme.secondaryText)
            Text("Le moteur n'a pas démarré")
                .font(.system(size: 16, weight: .medium))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .textSelection(.enabled)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
    }
}
