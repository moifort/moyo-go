import SwiftUI

/// "Connecter", at the foot of the sidebar: follows a game recorded by Kifu.
///
/// Several phones may run Kifu on the same network, so the button opens the list
/// of those in sight and the player picks one. A game under way here is not
/// dropped without asking.
struct PhoneButton: View {
    @Bindable var session: GameSession
    @State private var isConfirmingStop = false

    var body: some View {
        Group {
            switch session.phone.status {
            case .idle:
                Button {
                    session.connectPhone()
                } label: {
                    Label("Connecter", systemImage: "iphone")
                        .frame(maxWidth: .infinity)
                }
                .help("Suivre la partie qu'enregistre Kifu sur un iPhone")
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
        .sheet(isPresented: $session.isChoosingPhone) {
            PhonePicker(phones: session.phone.phones) { phone in
                session.follow(phone: phone.id)
            } cancel: {
                session.isChoosingPhone = false
            }
        }
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
            Button("Abandonner et suivre", role: .destructive) { session.choosePhone() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Suivre la partie du plateau remplace celle-ci.")
        }
    }
}

/// The phones running Kifu in sight, to pick the one whose game to follow. The
/// list fills in as phones appear; while it is empty, it says what it waits for.
private struct PhonePicker: View {
    let phones: [PhoneLink.Phone]
    let pick: (PhoneLink.Phone) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connecter un iPhone")
                .font(.system(size: 17, weight: .medium))
            if phones.isEmpty {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Attente de connexion d'une application Kifu sur un iPhone")
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                    Text("Ouvrez Kifu sur l'iPhone, connecté au même réseau Wi-Fi que ce Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 7) {
                    ForEach(phones) { phone in
                        Button {
                            pick(phone)
                        } label: {
                            Label(phone.name, systemImage: "iphone")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Recherche d'autres iPhone…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Annuler", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
