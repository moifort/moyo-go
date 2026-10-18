import SwiftUI

/// Changes the opponent in the middle of a game.
///
/// The same rows as the new-game sheet, without the board: the game goes on, and
/// the new mode applies from KataGo's next move.
public struct AISettingsSheet: View {
    @Bindable public var session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GameSession.Settings

    public init(session: GameSession) {
        self.session = session
        var draft = session.settings
        // Start from what is actually in force, which may differ from the saved
        // settings if the bridge was told otherwise.
        draft.aiStrategy = session.currentMode.id
        _draft = State(initialValue: draft)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Adversaire")
                    .font(.system(size: 17, weight: .medium))
                Text("Le changement vaut dès le prochain coup de KataGo.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Form {
                AIModeFields(session: session, draft: $draft)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Appliquer") {
                    let mode = AIMode.mode(for: draft.aiStrategy)
                    session.setAI(mode: mode, value: draft.value(for: mode))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
