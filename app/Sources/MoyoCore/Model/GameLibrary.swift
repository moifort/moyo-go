import CryptoKit
import Foundation

/// Every game played, reviewed or followed, kept without asking.
///
/// It lives in the app's own container — `Application Support/Moyo/Library/` — so
/// the sandbox needs no panel and no bookmark: `library.json` indexes the games,
/// `Games/<id>.sgf` holds each record as the bridge wrote it. The save panel stays
/// the way to put a game somewhere of the player's choosing.
///
/// Writes happen on the main actor, one after the other, and each file is written
/// atomically: a crash leaves the previous version, never half of one.
@MainActor
@Observable
public final class GameLibrary {
    /// The index as it is written. The version lets a later shape be told apart.
    private struct Index: Codable {
        var version: Int
        var entries: [LibraryEntry]
    }

    static let indexVersion = 1

    public private(set) var entries: [LibraryEntry] = []

    /// Where the library is kept, nil for one held in memory only.
    public let directory: URL?
    /// The records of a library held in memory: the tests, and the screenshots.
    private var memory: [UUID: String] = [:]

    public init(directory: URL?) {
        self.directory = directory
        load()
    }

    /// The library of the app, in its container. `MOYO_LIBRARY` puts it elsewhere,
    /// for a development build that should not touch the real one.
    public static func onDisk(environment: [String: String] = ProcessInfo.processInfo.environment) -> GameLibrary {
        if let path = environment["MOYO_LIBRARY"], !path.isEmpty {
            return GameLibrary(directory: URL(fileURLWithPath: path, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return GameLibrary(directory: support.appending(path: "Moyo/Library", directoryHint: .isDirectory))
    }

    private var indexURL: URL? { directory?.appending(path: "library.json") }
    private var gamesURL: URL? { directory?.appending(path: "Games", directoryHint: .isDirectory) }

    private func recordURL(_ id: UUID) -> URL? {
        gamesURL?.appending(path: "\(id.uuidString).sgf")
    }

    // -- reading ---------------------------------------------------------------

    /// Reads the index. One that will not read is started over: the records stay
    /// on disk, but are no longer listed — losing the list is better than refusing
    /// to open.
    func load() {
        guard let indexURL, let data = try? Data(contentsOf: indexURL) else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode(Index.self, from: data))?.entries ?? []
    }

    public func entry(_ id: UUID) -> LibraryEntry? {
        entries.first { $0.id == id }
    }

    public func entry(sourceHash: String) -> LibraryEntry? {
        entries.first { $0.sourceHash == sourceHash }
    }

    /// The record kept for a game, as the bridge last wrote it.
    public func contents(of id: UUID) -> String? {
        if directory == nil { return memory[id] }
        guard let url = recordURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // -- writing ---------------------------------------------------------------

    /// Writes a game's record, then the index that lists it.
    public func save(_ entry: LibraryEntry, contents: String) throws {
        if directory == nil {
            memory[entry.id] = contents
        } else if let url = recordURL(entry.id), let gamesURL {
            try FileManager.default.createDirectory(at: gamesURL, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url, options: .atomic)
        }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try writeIndex()
    }

    /// Removes a game for good: there is no bin.
    public func delete(_ id: UUID) throws {
        memory[id] = nil
        if let url = recordURL(id), FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        entries.removeAll { $0.id == id }
        try writeIndex()
    }

    private func writeIndex() throws {
        guard let directory, let indexURL else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Index(version: Self.indexVersion, entries: entries))
        try data.write(to: indexURL, options: .atomic)
    }

    /// The fingerprint of a record's text, to know a file already opened.
    public nonisolated static func fingerprint(_ contents: String) -> String {
        SHA256.hash(data: Data(contents.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
