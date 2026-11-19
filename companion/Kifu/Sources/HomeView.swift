import SwiftUI
import KifuCore

struct HomeView: View {
    @State private var games: [URL] = []
    /// "N coups" per game, read off the main thread: a long list of files would stall it.
    @State private var summaries: [URL: String] = [:]
    /// The games swiped away, waiting for the player to confirm.
    @State private var pendingDeletion: [URL] = []
    @State private var showGame = false
    @AppStorage(TrialLog.defaultsKey) private var trialMode = false
    @AppStorage(CameraSession.ultraWideDefaultsKey) private var ultraWide = false
    @AppStorage(GameSession.sceneReaderDefaultsKey) private var sceneReader = true
    @AppStorage(BoardServer.viewpointDefaultsKey) private var viewpoint = BoardBroadcast.Viewpoint.leftPlayer.rawValue

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
                Section {
                    Toggle("Grand-angle (0,5×)", isOn: $ultraWide)
                } footer: {
                    Text("Objectif 13 mm, pour le support imprimé posé au bord du goban. Sinon l'objectif principal 24 mm.")
                }
                Section {
                    Picker("Moyo montre le plateau vu par", selection: $viewpoint) {
                        Text("Joueur de gauche").tag(BoardBroadcast.Viewpoint.leftPlayer.rawValue)
                        Text("Joueur de droite").tag(BoardBroadcast.Viewpoint.rightPlayer.rawValue)
                    }
                } footer: {
                    Text("Gauche et droite de l'image du téléphone, posé sur le troisième côté de la table.")
                }
                Section {
                    Toggle("Lecture en 3D", isOn: $sceneReader)
                } footer: {
                    Text("Compare l'image à un rendu 3D du goban : les pierres cachées derrière une autre sont lues sur leur partie visible. Désactivée, l'ancienne lecture mesure chaque intersection.")
                }
                Section {
                    Toggle("Mode d'essai", isOn: $trialMode)
                } footer: {
                    Text("Garde les images de la partie dans Fichiers > Kifu > Essai : au départ, à chaque coup, à chaque alerte et toutes les 10 s. Environ 6 Mo par image.")
                }
                Section("Parties enregistrées") {
                    if games.isEmpty {
                        Text("Aucune partie pour l'instant.").foregroundStyle(.secondary)
                    }
                    ForEach(games, id: \.self) { url in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                Text(summaries[url] ?? " ").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                    .onDelete { offsets in
                        pendingDeletion = offsets.map { games[$0] }
                    }
                }
            }
            .navigationTitle("Kifu")
            .confirmationDialog(
                pendingDeletion.count > 1 ? "Supprimer ces parties ?" : "Supprimer cette partie ?",
                isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    for url in pendingDeletion { try? FileManager.default.removeItem(at: url) }
                    pendingDeletion = []
                    reload()
                }
                Button("Annuler", role: .cancel) { pendingDeletion = [] }
            } message: {
                Text("Le fichier SGF est effacé du téléphone.")
            }
        }
        .fullScreenCover(isPresented: $showGame, onDismiss: reload) { GameFlowView() }
        .onAppear(perform: reload)
    }

    private func reload() {
        let dir = GameSession.documents
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        games = urls.filter { $0.pathExtension == "sgf" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        let listed = games
        Task { summaries = await Self.summaries(of: listed) }
    }

    /// Off the main actor: a nonisolated async function runs on the global executor.
    nonisolated private static func summaries(of urls: [URL]) async -> [URL: String] {
        var read: [URL: String] = [:]
        for url in urls { read[url] = summary(of: url) }
        return read
    }

    nonisolated private static func summary(of url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let moves = SGFSummary.moveCount(in: text)
        return "\(moves) coup\(moves > 1 ? "s" : "")"
    }
}
