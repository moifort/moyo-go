import SwiftUI
import KifuCore

struct CalibrationView: View {
    @Bindable var session: GameSession
    let resuming: Bool
    @State private var fingerAt: CGPoint?

    private let labels = ["haut-gauche", "haut-droite", "bas-droite", "bas-gauche"]

    var body: some View {
        ZStack(alignment: .top) {
            FrameView(preview: session.preview, imageSize: session.frameSize) { frame in
                ZStack {
                    BoardOverlay(imageSize: session.frameSize, gridPoints: session.gridPoints,
                                 stones: session.isCalibrated ? session.readPosition : nil, taps: session.taps)
                    if !session.isCalibrated {
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { fingerAt = $0.location }
                                .onEnded { value in
                                    fingerAt = nil
                                    let shown = ImageMapping.displayedRect(imageSize: session.frameSize, in: frame)
                                    guard shown.contains(value.location) else { return }
                                    session.addTap(ImageMapping.toImage(value.location, imageSize: session.frameSize, in: frame))
                                })
                    }
                    if let fingerAt, let preview = session.preview {
                        Loupe(preview: preview, imageSize: session.frameSize, frame: frame, point: fingerAt)
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                Text(instruction)
                    .font(.headline)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.white)
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
                    Button(session.taps.isEmpty ? "Annuler" : "Reprendre les coins") {
                        if session.taps.isEmpty { session.cancel() } else { session.clearTaps() }
                    }
                    .buttonStyle(.bordered)
                    Button(resuming ? "Reprendre la partie" : "Commencer") {
                        if resuming { session.resumeGame() } else { session.startGame() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.isCalibrated)
                }
                .padding(.bottom, 20)
            }
        }
    }

    private var instruction: String {
        if session.isCalibrated {
            let count = session.readPosition.stones.count
            return count == 0 ? "Grille calée, plateau vide" : "Grille calée, \(count) pierre\(count > 1 ? "s" : "") vue\(count > 1 ? "s" : "")"
        }
        if session.calibrationFailed { return "Coins invalides, recommence" }
        guard session.taps.count < labels.count else { return "Calage de la grille…" }
        return "Touche le coin \(labels[session.taps.count]) de la grille"
    }
}
