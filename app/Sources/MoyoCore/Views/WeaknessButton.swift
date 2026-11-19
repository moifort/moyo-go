import SwiftUI

/// Shows or hides the weak points. They stay on, position after position, until
/// pressed again; a spinner says KataGo is still looking at the position on screen.
struct WeaknessButton: View {
    @Bindable var session: GameSession
    /// One word, to share a row with the estimate.
    var compact = false

    var body: some View {
        Button {
            session.toggleWeaknesses()
        } label: {
            HStack(spacing: 6) {
                // Its own icon: `scope` is the local sequence's, among the steps above.
                Label(
                    compact
                        ? "Faiblesses"
                        : session.isShowingWeaknesses ? "Masquer les faiblesses" : "Montrer les faiblesses",
                    systemImage: session.isShowingWeaknesses ? "eye.slash" : "exclamationmark.shield"
                )
                if session.isShowingWeaknesses, session.state?.weaknessesPending == true {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .disabled(!session.canShowWeaknesses)
        .accessibilityLabel(session.isShowingWeaknesses ? "Masquer les faiblesses" : "Montrer les faiblesses")
        .help("Où une pierre frapperait un groupe faible ; la couleur du point est celle de la pierre (⇧⌘E)")
    }
}
