import SwiftUI

struct HomeView: View {
    @State private var games: [URL] = []
    @State private var showGame = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showGame = true
                    } label: {
                        Label("Nouvelle partie", systemImage: "camera.viewfinder").font(.headline)
                    }
                }
                Section("Parties enregistrées") {
                    if games.isEmpty {
                        Text("Aucune partie pour l'instant.").foregroundStyle(.secondary)
                    }
                    ForEach(games, id: \.self) { url in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                Text(summary(of: url)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { try? FileManager.default.removeItem(at: games[i]) }
                        reload()
                    }
                }
            }
            .navigationTitle("Kifu")
        }
        .fullScreenCover(isPresented: $showGame, onDismiss: reload) { GameFlowView() }
        .onAppear(perform: reload)
    }

    private func reload() {
        let dir = GameSession.documents
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        games = urls.filter { $0.pathExtension == "sgf" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func summary(of url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let moves = text.components(separatedBy: ";").count - 2
        return "\(max(moves, 0)) coup\(moves > 1 ? "s" : "")"
    }
}
