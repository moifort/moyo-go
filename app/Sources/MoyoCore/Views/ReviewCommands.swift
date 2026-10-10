import SwiftUI

extension Notification.Name {
    /// Posted by the File menu; the window answers with an open panel.
    public static let moyoOpenRecordRequested = Notification.Name("Moyo.openRecordRequested")
    /// Carries a URL the window should read: dropped on the board, or opened from
    /// the Finder. Both arrive with the sandbox grant already attached.
    public static let moyoRecordDropped = Notification.Name("Moyo.recordDropped")
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
        NotificationCenter.default.post(name: .moyoRecordDropped, object: url)
    }
}

/// Menu items for reading a record, and the arrow keys that go with them.
///
/// The shortcuts are bare arrows, which is what a review is played on. They can be
/// bare because every item here is disabled outside a review, and a disabled menu
/// item does not swallow its key — the arrows stay with the text fields and the
/// steppers of the new-game sheet.
public struct ReviewCommands: Commands {
    @FocusedValue(\.gameSession) private var session

    public init() {}

    private var isReviewing: Bool { session?.isReviewing == true }

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

        CommandMenu("Revue") {
            Button("Coup précédent") { session?.step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(session?.canStepBackward != true)

            Button("Coup suivant") { session?.step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(session?.canStepForward != true)

            Divider()

            Button("Début de la partie") { session?.goto(moveNumber: 0) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!isReviewing)

            Button("Fin de la partie") {
                if let count = session?.state?.moveCount { session?.goto(moveNumber: count) }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!isReviewing)

            Divider()

            Button("Dérouler la proposition") { session?.stepVariation(1) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(!isReviewing)

            Button("Remonter la proposition") { session?.stepVariation(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(session?.state?.variationDepth ?? 0 == 0)
        }
    }
}
