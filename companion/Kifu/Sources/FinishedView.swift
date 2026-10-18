import SwiftUI

struct FinishedView: View {
    let session: GameSession
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Partie enregistrée").font(.title2.bold())
            if let result = session.result { Text(RecordingView.title(result)).font(.headline) }
            Text("\(session.moveCount) coup\(session.moveCount > 1 ? "s" : "")").foregroundStyle(.secondary)
            if let url = session.fileURL {
                Text(url.lastPathComponent).font(.footnote).foregroundStyle(.secondary)
                ShareLink(item: url) { Label("Partager le SGF", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent)
            }
            Button("Terminer", action: dismiss).buttonStyle(.bordered)
        }
        .padding()
    }
}
