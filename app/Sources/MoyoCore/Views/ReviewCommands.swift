import SwiftUI

extension Notification.Name {
    /// Posted by the File menu; the window answers with an open panel.
    public static let moyoOpenRecordRequested = Notification.Name("Moyo.openRecordRequested")
    /// A record opened from the Finder is waiting in `RecordInbox`.
    public static let moyoRecordArrived = Notification.Name("Moyo.recordArrived")
}

/// Where a record opened from the Finder waits for someone to read it.
///
/// A double-click on a record launches the app with it, and Launch Services hands
/// it over before the window exists. A notification alone would be posted to nobody;
/// the inbox keeps the file until the root view comes up and takes it.
@MainActor
public enum RecordInbox {
    private static var pending: URL?

    /// The URL arrives with its sandbox grant already attached.
    public static func deliver(_ url: URL) {
        pending = url
        NotificationCenter.default.post(name: .moyoRecordArrived, object: nil)
    }

    /// The waiting record, handed over once.
    public static func take() -> URL? {
        defer { pending = nil }
        return pending
    }
}

/// Catches records opened from the Finder.
///
/// SwiftUI's `onOpenURL` covers custom schemes, not documents handed over by
/// Launch Services; that still comes through the application delegate.
public final class RecordOpeningDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == SGFImport.fileExtension })
        else { return }
        RecordInbox.deliver(url)
    }
}

/// The Analyse menu: the toggle, the tree, KataGo's lines, and every key with them.
///
/// Every shortcut of the analysis lives here, with its key shown, so it can be found
/// without being known. The arrows are bare, which is what a tree is walked with.
/// They can be bare because every item is disabled outside the analysis, and a
/// disabled menu item does not swallow its key — the arrows stay with the text
/// fields and the steppers of the new-game sheet.
public struct ReviewCommands: Commands {
    @FocusedValue(\.gameSession) private var session

    public init() {}

    private var isAnalysing: Bool { session?.isAnalysing == true }

    private var canDeleteOnScreen: Bool {
        guard let session, let id = session.state?.nodeId else { return false }
        return session.isAnalysing && session.isDeletable(id)
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Ouvrir une partie…") {
                NotificationCenter.default.post(name: .moyoOpenRecordRequested, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            // A game against the AI and a record under review alike: the first goes
            // out as played, the second as read, with the variation being walked.
            Button("Enregistrer la partie…") { session?.exportRecord() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(session?.canExport != true)
        }

        CommandMenu("Analyse") {
            Button("Partie en cours") { session?.setView(.live) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(session?.canSwitchView != true || !isAnalysing)

            Button("Analyse") { session?.setView(.analysis) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(session?.canSwitchView != true || isAnalysing)

            Divider()

            Button("Coup précédent") { session?.step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(session?.canStepBackward != true)

            Button("Coup suivant") { session?.step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(session?.canStepForward != true)

            Button("Variante précédente") { session?.navigate(.previousSibling) }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(session?.hasPreviousSibling != true)

            Button("Variante suivante") { session?.navigate(.nextSibling) }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(session?.hasNextSibling != true)

            Button("Début de la partie") { session?.navigate(.start) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!isAnalysing)

            Button("Fin de la variante") { session?.navigate(.end) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(session?.canStepForward != true)

            Button("Revenir à la partie") { session?.navigate(.game) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(session?.isInBranch != true)

            Divider()

            Button("Supprimer la variante") {
                if let id = session?.state?.nodeId { session?.deleteBranch(id) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!canDeleteOnScreen)

            Divider()

            Button("Dérouler la proposition") { session?.stepVariation(1) }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .shift])
                .disabled(!isAnalysing)

            Button("Remonter la proposition") { session?.stepVariation(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .shift])
                .disabled(session?.state?.variationDepth ?? 0 == 0)

            Divider()

            // The bare Option arrows go to the local sequence: reading the fight out
            // is what an analysis is mostly for, the whole-board line comes second.
            Button("Dérouler la séquence locale") { session?.stepVariation(1, kind: .local) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(session?.canWalkLocal != true)

            Button("Remonter la séquence locale") { session?.stepVariation(-1, kind: .local) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(session?.isWalkingLocal != true)

            // The zone itself is drawn by dragging across the board; only undoing
            // it needs a key.
            Button("Revenir à la zone automatique") { session?.clearDrawnZone() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(session?.hasDrawnZone != true)
        }
    }
}
