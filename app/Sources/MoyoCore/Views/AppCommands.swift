import SwiftUI

extension Notification.Name {
    public static let moyoNewGameRequested = Notification.Name("Moyo.newGameRequested")
}

/// Lets the menu bar reach the session of whichever window has focus.
public struct GameSessionFocusedValueKey: FocusedValueKey {
    public typealias Value = GameSession
}

extension FocusedValues {
    public var gameSession: GameSession? {
        get { self[GameSessionFocusedValueKey.self] }
        set { self[GameSessionFocusedValueKey.self] = newValue }
    }
}

/// Menu items for the game, mirroring the sidebar actions.
///
/// Every action lives here as well as in the sidebar so it keeps a keyboard
/// shortcut when the sidebar is collapsed.
public struct GameCommands: Commands {
    @FocusedValue(\.gameSession) private var session

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nouvelle partie…") {
                NotificationCenter.default.post(name: .moyoNewGameRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Partie") {
            // In analysis the pass joins the branch, and the undo takes back the
            // stone just placed by hand, never a move of the game.
            Button("Passer") { session?.passTurn() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(session?.canAct != true && session?.isAnalysing != true)

            Button("Annuler le coup") { session?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(session?.canAct != true && !(session?.isAnalysing == true && session?.canUndo == true))

            Divider()

            Button(session?.isEstimating == true ? "Masquer l'estimation" : "Estimer le score") {
                session?.toggleEstimate()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(session?.canEstimate != true && session?.isEstimating != true)

            Divider()

            Button("Abandonner") { session?.resign() }
                .disabled(session?.state?.status != .playing)

            Divider()

            // Available only while counting; the sidebar keeps a single action there,
            // so these two live in the menu.
            Button("Reprendre la partie") { session?.resumeGame() }
                .disabled(session?.state?.status != .scoring)

            Button("Accepter le score") { session?.acceptScore() }
                .disabled(session?.state?.status != .scoring)
        }
    }
}
