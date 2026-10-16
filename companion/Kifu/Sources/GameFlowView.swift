import SwiftUI

/// One game from calibration to the saved file.
struct GameFlowView: View {
    @State private var session = GameSession()
    @State private var resuming = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch session.phase {
            case .calibrating:
                CalibrationView(session: session, resuming: resuming)
            case .recording:
                RecordingView(session: session)
            case .finished:
                FinishedView(session: session) { dismiss() }
            }
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .recording { resuming = true }
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
