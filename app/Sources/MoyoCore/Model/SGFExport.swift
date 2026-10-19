import Foundation

/// Writes a game record to disk, where the player chose in the save panel.
///
/// The mirror of `SGFImport`, and the only other place the app touches a file. The
/// bridge turns the game into text and hands it over; the sandbox grants the save
/// panel's location to the window, not to the child process, so the writing
/// happens here.
public enum SGFExport {
    public enum Failure: LocalizedError, Equatable {
        case notWritable(String)
        case changedOnDisk(String)

        public var errorDescription: String? {
            switch self {
            case .notWritable(let name):
                return "« \(name) » n'a pas pu être écrit."
            case .changedOnDisk(let name):
                return "« \(name) » a changé depuis son ouverture : l'analyse n'y a pas été enregistrée."
            }
        }
    }

    /// The text the bridge produced, and the name the save panel will offer.
    public struct Document: Equatable, Sendable {
        public let name: String
        public let contents: String

        public init(name: String, contents: String) {
            self.name = name
            self.contents = contents
        }
    }

    /// A record read back keeps its own name, so saving it lands next to itself;
    /// a game against the AI is named after the moment it was saved.
    public static func suggestedName(recordName: String?, date: Date, timeZone: TimeZone = .current) -> String {
        if let recordName, !recordName.isEmpty {
            let isSGF = (recordName as NSString).pathExtension.lowercased() == SGFImport.fileExtension
            return isSGF ? recordName : "\(recordName).\(SGFImport.fileExtension)"
        }
        // No colon: the Finder shows it as a slash, and other systems refuse it.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH'h'mm"
        return "Moyo \(formatter.string(from: date)).\(SGFImport.fileExtension)"
    }

    /// How the opponent signs the record: the engine, its mode, and its setting.
    public static func aiName(mode: AIMode, value: Double?) -> String {
        guard let setting = mode.setting, let value else { return "KataGo · \(mode.name)" }
        return "KataGo · \(mode.name), \(setting.describe(value))"
    }

    /// `PB` and `PW`. A blank name is left out rather than written empty.
    public static func players(
        humanColor: PlayerColor, human: String, ai: String
    ) -> (black: String?, white: String?) {
        let human = human.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = human.isEmpty ? nil : human
        return humanColor == .black ? (named, ai) : (ai, named)
    }

    /// Writes a record analysed to the end over the file it was read from.
    ///
    /// The open panel, a drop or the Finder granted access to that file; the grant
    /// travels with the URL and is claimed again here. A file changed by someone
    /// else since it was opened is left alone: their edit outweighs our analysis.
    public static func rewrite(_ contents: String, over record: SGFImport.Record) throws {
        guard let url = record.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard SGFImport.modificationDate(of: url) == record.modified else {
            throw Failure.changedOnDisk(url.lastPathComponent)
        }
        try write(contents, to: url)
    }

    /// UTF-8, which is what the bridge declares in `CA[]`. Atomic, so a failed
    /// write never leaves half a game where a whole one used to be.
    public static func write(_ contents: String, to url: URL) throws {
        do {
            try Data(contents.utf8).write(to: url, options: .atomic)
        } catch {
            throw Failure.notWritable(url.lastPathComponent)
        }
    }
}
