import Foundation

/// Joue une ouverture scriptée au lancement, pour produire des captures d'écran.
///
/// Une capture de la fiche App Store doit montrer une vraie partie, pas un goban
/// vide. Or le goban est un canevas SwiftUI : un clic synthétique envoyé à une
/// fenêtre inactive n'y déclenche aucun geste, et piloter l'application à la
/// souris suppose de lui voler le premier plan.
///
/// Passer par la session résout les deux, et rend surtout les captures
/// reproductibles : la même position à chaque version, et depuis la CI.
public enum DemoScript {
    public static let flag = "--demo"

    public static func isRequested(
        in arguments: [String] = CommandLine.arguments
    ) -> Bool {
        arguments.contains(flag)
    }

    /// Les coups de l'humain. Une ouverture ordinaire qui occupe les quatre coins
    /// puis engage un contact, de quoi remplir le goban et faire courir le graphe
    /// de score. L'IA répond entre chacun.
    static let moves: [(row: Int, col: Int)] = [
        (3, 3), (15, 15), (15, 3), (3, 15), (5, 2), (16, 13), (13, 16),
    ]

    @MainActor
    public static func run(on session: GameSession) async {
        guard await settled(until: { session.phase == .running }, within: 120) else { return }
        session.isShowingLibrary = false

        for move in moves {
            guard await settled(until: { session.state?.toPlay == session.settings.humanColor },
                                within: 60) else { return }
            let before = session.state?.moveNumber ?? 0
            session.play(row: move.row, col: move.col)
            // Le coup de l'humain puis la réponse de l'IA : le numéro avance de deux.
            guard await settled(until: { (session.state?.moveNumber ?? 0) >= before + 2 },
                                within: 90) else { return }
        }
    }

    /// Attend qu'une condition devienne vraie, sans bloquer la boucle d'interface.
    @MainActor
    private static func settled(
        until condition: () -> Bool,
        within seconds: Double
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
}
