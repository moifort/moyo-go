import SwiftUI

/// The phone running Kifu, at the foot of the sidebar.
///
/// It shows up by itself once Kifu is open on the network, named after the phone,
/// and says where the link stands. Connecting follows the game on the real board;
/// a game under way here is not dropped without asking.
struct PhoneButton: View {
    @Bindable var session: GameSession
    @State private var isConfirmingStop = false

    var body: some View {
        Group {
            switch session.phone.status {
            case .idle, .searching:
                EmptyView()
            case .available(let name):
                Button {
                    session.connectPhone()
                } label: {
                    Label("Connecter à \(name)", systemImage: "iphone")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .help("Suivre la partie que Kifu enregistre sur \(name)")
            case .connecting(let name):
                Button {
                    session.stopFollowing()
                } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Connexion à \(name)…").lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .help("Arrêter")
            case .connected(let name):
                Button {
                    isConfirmingStop = true
                } label: {
                    Label {
                        Text("Connecté à \(name)").lineLimit(1)
                    } icon: {
                        Image(systemName: "iphone").foregroundStyle(Theme.connected)
                    }
                    .frame(maxWidth: .infinity)
                }
                .help("Cliquer pour arrêter de suivre la partie")
            case .failed(let message):
                Button {
                    session.connectPhone()
                } label: {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .help("Échec : \(message)")
            }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .confirmationDialog(
            "Arrêter de suivre la partie ?",
            isPresented: $isConfirmingStop,
            titleVisibility: .visible
        ) {
            Button("Arrêter le suivi") { session.stopFollowing() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text(
                session.state?.isFollowing == true
                    ? "La partie suivie jusqu'ici s'ouvre en revue."
                    : "Moyo ne suivra plus les parties enregistrées par Kifu."
            )
        }
        .confirmationDialog(
            "Une partie est en cours",
            isPresented: $session.isConfirmingFollow,
            titleVisibility: .visible
        ) {
            Button("Enregistrer, puis suivre") { session.saveThenFollow() }
            Button("Abandonner et suivre", role: .destructive) { session.startFollowing() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Suivre la partie du plateau remplace celle-ci.")
        }
    }
}
