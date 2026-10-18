import SwiftUI

/// One game from calibration to the saved file.
struct GameFlowView: View {
    @State private var session = GameSession()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch session.phase {
            case .calibrating:
                CalibrationView(session: session, resuming: session.gameInProgress)
            case .recording:
                RecordingView(session: session)
            case .finished:
                FinishedView(session: session, newGame: session.newGame) { dismiss() }
            }
        }
        .onChange(of: session.cancelled) { _, cancelled in
            if cancelled { dismiss() }
        }
        .task { await session.startCamera() }
        .onDisappear { session.stopCamera() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
