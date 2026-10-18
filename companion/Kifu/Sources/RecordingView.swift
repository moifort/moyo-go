import SwiftUI
import KifuCore

struct RecordingView: View {
    @Bindable var session: GameSession
    /// The ending tapped, waiting for confirmation: a stray tap must not stop the record.
    @State private var ending: GameResult?

    var body: some View {
        ZStack(alignment: .top) {
            FrameView(preview: session.preview, imageSize: session.frameSize) { _ in
                BoardOverlay(imageSize: session.frameSize, gridPoints: session.gridPoints,
                             stones: session.acceptedPosition,
                             ghosts: session.status == .inSync ? nil : session.candidatePosition,
                             lastMove: session.lastMove?.point,
                             highlighted: session.status == .lost ? disagreements : [])
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Text(statusText).font(.headline)
                    Text("·").foregroundStyle(.secondary)
                    Text("\(session.moveCount) coup\(session.moveCount > 1 ? "s" : "")").font(.subheadline)
                    if session.connectedMacs > 0 {
                        Text("·").foregroundStyle(.secondary)
                        Label("Moyo", systemImage: "desktopcomputer").font(.subheadline)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.black.opacity(0.65), in: Capsule())
                .foregroundStyle(.white)

                if session.status == .lost {
                    VStack(spacing: 10) {
                        Text("Je ne comprends pas la position").font(.headline)
                        Text("Les intersections en orange ne s'expliquent pas par un coup.").font(.caption)
                        HStack(spacing: 16) {
                            Button("Recalibrer") { session.recalibrate() }.buttonStyle(.bordered)
                            Button("C'est bon") { session.acceptCandidate() }.buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                    .background(.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
            }
            .padding(.top, 8)

            VStack {
                Spacer()
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Noir abandonne") { ending = .blackResigned }
                        Button("Blanc abandonne") { ending = .whiteResigned }
                    }
                    .buttonStyle(.bordered)
                    HStack(spacing: 12) {
                        Button("Recalibrer") { session.recalibrate() }.buttonStyle(.bordered)
                        Button("Partie terminée") { ending = .finished }.buttonStyle(.borderedProminent)
                    }
                }
                .padding(.bottom, 20)
                .confirmationDialog(ending.map(Self.title) ?? "", isPresented: isEnding, titleVisibility: .visible) {
                    Button("Arrêter l'enregistrement", role: .destructive) {
                        if let ending { session.endGame(ending) }
                    }
                }
            }
        }
    }

    private var isEnding: Binding<Bool> {
        Binding(get: { ending != nil }, set: { if !$0 { ending = nil } })
    }

    static func title(_ result: GameResult) -> String {
        switch result {
        case .blackResigned: return "Noir abandonne, Blanc gagne"
        case .whiteResigned: return "Blanc abandonne, Noir gagne"
        case .finished: return "Partie terminée, décompte à faire à la relecture"
        }
    }

    private var disagreements: Set<Intersection> {
        Set(session.acceptedPosition.diff(to: session.candidatePosition).keys)
    }

    private var statusText: String {
        switch session.status {
        case .inSync: return "Partie suivie"
        case .pending: return "Changement en cours"
        case .awaitingCaptureRemoval: return "Retire les pierres capturées"
        case .lost: return "Arbitrage demandé"
        }
    }
}
