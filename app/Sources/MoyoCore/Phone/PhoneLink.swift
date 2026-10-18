import Foundation
import Network
import Observation

/// Finds the phones on the local network over Bonjour and streams the board of
/// the one the player picks.
///
/// Kifu advertises `_goboard._tcp` while it is open and writes one JSON line per
/// change of the position, and one when the game ends. Several phones may run it
/// at once, so the link keeps the list of every one in sight from launch, and
/// connects only to the one chosen. This class owns nothing about the game.
@Observable
@MainActor
public final class PhoneLink {
    public enum Status: Equatable {
        /// Not connected; the phones in sight are in `phones`.
        case idle
        case connecting(String)
        case connected(String)
        case failed(String)
    }

    public static let serviceType = "_goboard._tcp"

    public private(set) var status: Status = .idle
    /// The phones running Kifu in sight right now, by name, sorted.
    public private(set) var phones: [String] = []
    public private(set) var latest: PhoneBoard?
    public var onBoard: ((PhoneBoard) -> Void)?
    public var onGameEnd: ((PhoneGameEnd) -> Void)?

    private var browser: NWBrowser?
    private var found: [String: NWBrowser.Result] = [:]
    private var connection: NWConnection?
    /// The phone the player chose: a dropped link to it is opened again on its own.
    private var chosen: String?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "Moyo.phone")

    public init() {}

    public var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    /// The phone's own name, without the app's prefix: "Kifu — iPhone 2" reads "iPhone 2".
    nonisolated static func displayName(_ service: String) -> String {
        for prefix in ["Kifu — ", "Kifu - "] where service.hasPrefix(prefix) {
            return String(service.dropFirst(prefix.count))
        }
        return service
    }

    /// Starts looking for phones, without connecting. Does nothing if already looking.
    public func startDiscovery() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                if case .failed(let error) = state { self?.status = .failed(error.localizedDescription) }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in self?.resultsChanged(Array(results)) }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    /// Connects to the phone of that name, or to the one chosen last.
    public func connect(to name: String? = nil) {
        if let name { chosen = name }
        startDiscovery()
        guard connection == nil, let chosen else { return }
        if let result = found[chosen] {
            open(result, name: chosen)
        } else {
            status = .connecting(chosen)  // opened as soon as it shows up again
        }
    }

    /// Closes the link; the search goes on.
    public func disconnect() {
        chosen = nil
        connection?.cancel(); connection = nil
        buffer.removeAll()
        latest = nil
        status = .idle
    }

    private func resultsChanged(_ results: [NWBrowser.Result]) {
        var byName: [String: NWBrowser.Result] = [:]
        for result in results { byName[name(of: result)] = result }
        found = byName
        phones = byName.keys.sorted()
        if connection == nil, let chosen, let result = byName[chosen] {
            open(result, name: chosen)
        }
    }

    private func name(of result: NWBrowser.Result) -> String {
        if case .service(let serviceName, _, _, _) = result.endpoint { return Self.displayName(serviceName) }
        return "iPhone"
    }

    private func open(_ result: NWBrowser.Result, name: String) {
        guard connection == nil else { return }
        status = .connecting(name)
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self] in
                guard let self, let connection, self.connection === connection else { return }
                switch state {
                case .ready:
                    self.status = .connected(name)
                    self.receive()
                case .failed(let error):
                    self.connection = nil
                    self.status = .failed(error.localizedDescription)
                case .cancelled:
                    self.connectionDropped()
                default: break
                }
            }
        }
        self.connection = connection
        connection.start(queue: queue)
    }

    /// The phone went away — Kifu closed, the network dropped. Open again once it is back.
    private func connectionDropped() {
        connection = nil
        buffer.removeAll()
        guard let chosen else { status = .idle; return }
        status = .connecting(chosen)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.connection == nil, self.chosen == chosen, let result = self.found[chosen] else { return }
            self.open(result, name: chosen)
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data { self.consume(data) }
                if isComplete || error != nil {
                    self.connection?.cancel()
                } else {
                    self.receive()
                }
            }
        }
    }

    /// Splits the stream on newlines; a partial line waits for the rest.
    func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let board = PhoneBoard(line: line) {
                latest = board
                onBoard?(board)
            } else if let end = PhoneGameEnd(line: line) {
                onGameEnd?(end)
            }
        }
    }
}
