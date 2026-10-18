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
                .keyboardShortcut(.rightArrow, modifiers: [.option, .shift])
                .disabled(!isReviewing)

            Button("Remonter la proposition") { session?.stepVariation(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .shift])
                .disabled(session?.state?.variationDepth ?? 0 == 0)

            Divider()

            // The bare Option arrows go to the local sequence: reading the fight out
            // is what a review is mostly for, the whole-board line comes second.
            Button("Dérouler la séquence locale") { session?.stepVariation(1, kind: .local) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(session?.canWalkLocal != true)

            Button("Remonter la séquence locale") { session?.stepVariation(-1, kind: .local) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(session?.isWalkingLocal != true)
        }
    }
}
