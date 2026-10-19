import Foundation

/// Reads a game record off disk and hands back its text.
///
/// This is the only place in the app that opens a file, and the reason the bridge
/// never has to. The sandbox grants access to what the player picked in the open
/// panel or dropped on the window — a grant the child process does not inherit —
/// so the record is read here and travels to the bridge as text.
public enum SGFImport {
    public enum Failure: LocalizedError, Equatable {
        case notReadable(String)
        case undecodable(String)
        case empty(String)

        public var errorDescription: String? {
            switch self {
            case .notReadable(let name):
                return "« \(name) » n'a pas pu être lu."
            case .undecodable(let name):
                return "« \(name) » n'est pas dans un encodage reconnaissable."
            case .empty(let name):
                return "« \(name) » est vide."
            }
        }
    }

    public struct Record: Equatable, Sendable {
        public let name: String
        public let contents: String
        /// Where the record was read, and when the file was last changed then: the
        /// analysis is written back there, unless someone else wrote first.
        public let url: URL?
        public let modified: Date?

        public init(name: String, contents: String, url: URL? = nil, modified: Date? = nil) {
            self.name = name
            self.contents = contents
            self.url = url
            self.modified = modified
        }
    }

    /// The extension the open panel and the drop target accept.
    public static let fileExtension = "sgf"

    public static func read(_ url: URL) throws -> Record {
        // A URL from the open panel or from a drop carries a security scope that has
        // to be claimed before reading and given back after, or the app leaks one
        // grant per import until the sandbox stops handing them out.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        guard let data = try? Data(contentsOf: url) else {
            throw Failure.notReadable(name)
        }
        guard let text = decode(data) else {
            throw Failure.undecodable(name)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.empty(name)
        }
        return Record(name: name, contents: text, url: url, modified: modificationDate(of: url))
    }

    /// When the file was last written. Asked of the file system each time: a URL
    /// caches its resource values, and would keep answering with the first date.
    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Bytes to text: UTF-8 first, then whatever the system recognises.
    ///
    /// Records come from every server and every decade — UTF-8 from OGS, Latin-1 and
    /// GB18030 from older archives. The record's own `CA[]` property is not consulted:
    /// it could only disagree about names and comments, never about the moves, which
    /// are ASCII either way.
    public static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        var converted: NSString?
        let detected = NSString.stringEncoding(
            for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil
        )
        if detected != 0, let text = converted as String? {
            return text
        }
        // Latin-1 accepts any byte, so this never fails. A name carrying an odd
        // glyph is a better outcome than a record refused outright.
        return String(data: data, encoding: .isoLatin1)
    }
}
