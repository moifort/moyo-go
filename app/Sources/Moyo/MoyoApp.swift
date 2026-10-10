import MoyoCore
import SwiftUI

@main
struct MoyoApp: App {
    @NSApplicationDelegateAdaptor(RecordOpeningDelegate.self) private var delegate
    /// One game and one engine for the life of the app, whatever the window does.
    @State private var session = GameSession()

    init() {
        // `Moyo --smoke` vérifie le bundle depuis son propre sandbox, puis sort.
        // C'est le seul point d'où le test est fidèle : les helpers héritent du
        // sandbox de l'application et n'en ont aucun si on les lance à la main.
        if CommandLine.arguments.contains(BundleSelfTest.flag) {
            exit(BundleSelfTest.run())
        }
    }

    var body: some Scene {
        // One window, not a group: Moyo holds one game and one KataGo. A group opens a
        // fresh window — and a fresh engine — for every record handed over by the
        // Finder, where this hands it to the window already there.
        Window("Moyo", id: "main") {
            RootView(session: session)
                .frame(minWidth: 720, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
            GameCommands()
            ReviewCommands()
        }
    }
}
