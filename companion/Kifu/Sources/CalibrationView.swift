import SwiftUI
import KifuCore

struct CalibrationView: View {
    @Bindable var session: GameSession
    let resuming: Bool

    private let labels = ["haut-gauche", "haut-droite", "bas-droite", "bas-gauche"]

    var body: some View {
        ZStack(alignment: .top) {
            if let frozen = session.frozen {
                CornerPicker(image: frozen, taps: session.taps) { session.addTap($0) }
                    .ignoresSafeArea()
            } else {
                FrameView(preview: session.preview, imageSize: session.frameSize) { _ in
                    BoardOverlay(imageSize: session.frameSize, gridPoints: session.gridPoints,
                                 stones: session.isCalibrated ? session.readPosition : nil)
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 8) {
                Text(instruction)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.white)
                if session.frozen != nil, session.taps.count < 4 {
                    Text("Zoome à deux doigts pour viser l'intersection.")
                        .font(.caption).foregroundStyle(.white.opacity(0.9))
                }
                if let warning = session.qualityWarning {
                    Text(warning)
                        .font(.subheadline).foregroundStyle(.white)
                        .padding(8).background(.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                }
                if !session.cameraAvailable {
                    Text("Caméra indisponible").font(.subheadline).foregroundStyle(.white)
                        .padding(8).background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.top, 8)

            VStack {
                Spacer()
                HStack(spacing: 20) {
                    if session.frozen != nil {
                        Button("Reprendre la vidéo") { session.unfreeze() }.buttonStyle(.bordered)
                        Button("Effacer les coins") { session.clearTaps() }
                            .buttonStyle(.bordered)
                            .disabled(session.taps.isEmpty)
                    } else if session.isCalibrated {
                        Button("Reprendre les coins") { session.freeze() }
                            .buttonStyle(.bordered)
                            .disabled(session.starting)
                        Button {
                            if resuming { session.resumeGame() } else { session.startGame() }
                        } label: {
                            if session.starting {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Démarrage…")
                                }
                            } else {
                                Text(resuming ? "Reprendre la partie" : "Commencer")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.starting)
                    } else {
                        Button("Annuler") { session.cancel() }.buttonStyle(.bordered)
                        if session.canReuseCalibration {
                            Button("Ancien calibrage") { session.reuseCalibration() }.buttonStyle(.bordered)
                        }
                        Button("Figer l'image") { session.freeze() }
                            .buttonStyle(.borderedProminent)
                            .disabled(session.preview == nil)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private var instruction: String {
        if session.calibrationFailed { return "Coins invalides, recommence" }
        if session.frozen != nil {
            guard session.taps.count < labels.count else { return "Calage de la grille…" }
            return "Touche le coin \(labels[session.taps.count]) de la grille"
        }
        if session.isCalibrated {
            let count = session.readPosition.stones.count
            return count == 0 ? "Grille calée, plateau vide" : "Grille calée, \(count) pierre\(count > 1 ? "s" : "") vue\(count > 1 ? "s" : "")"
        }
        if session.canReuseCalibration { return "Remets le téléphone sur le support, ou fige l'image" }
        return "Place le téléphone, puis fige l'image"
    }
}
