import Foundation
import Network
import Observation

/// Finds the phone on the local network over Bonjour and streams the board it sees.
///
/// The phone runs Kifu, which advertises `_goboard._tcp` while it is open and writes
/// one JSON line per change of the position, and one when the game ends. The link
/// keeps looking from launch, so the sidebar can offer the phone by name as soon as
/// it shows up; it connects only when asked. This class owns nothing about the game.
@Observable
@MainActor
public final class PhoneLink {
    public enum Status: Equatable {
        /// Not looking.
        case idle
        /// Looking, and no phone in sight.
        case searching
        /// A phone is there, not connected.
        case available(String)
        case connecting(String)
        case connected(String)
        case failed(String)
    }

    public static let serviceType = "_goboard._tcp"

    public private(set) var status: Status = .idle
    public private(set) var latest: PhoneBoard?
    public var onBoard: ((PhoneBoard) -> Void)?
    public var onGameEnd: ((PhoneGameEnd) -> Void)?

    private var browser: NWBrowser?
    private var found: NWBrowser.Result?
    private var connection: NWConnection?
    /// The player asked to connect: a dropped link is opened again on its own.
    private var wantsConnection = false
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

    /// Starts looking for the phone, without connecting. Does nothing if already looking.
    public func startDiscovery() {
        guard browser == nil else { return }
        if status == .idle { status = .searching }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                if case .failed(let error) = state { self?.status = .failed(error.localizedDescription) }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in self?.resultsChanged(results.first) }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    public func connect() {
        wantsConnection = true
        startDiscovery()
        if let found { open(found) }
    }

    /// Closes the link and goes back to offering the phone; the search goes on.
    public func disconnect() {
        wantsConnection = false
        connection?.cancel(); connection = nil
        buffer.removeAll()
        latest = nil
        showFound()
    }

    private func resultsChanged(_ result: NWBrowser.Result?) {
        found = result
        if connection != nil { return }
        if wantsConnection, let result {
            open(result)
        } else {
            showFound()
        }
    }

    private func showFound() {
        guard browser != nil else { status = .idle; return }
        status = found.map { .available(name(of: $0)) } ?? .searching
    }

    private func name(of result: NWBrowser.Result) -> String {
        if case .service(let serviceName, _, _, _) = result.endpoint { return Self.displayName(serviceName) }
        return "iPhone"
    }

    private func open(_ result: NWBrowser.Result) {
        guard connection == nil else { return }
        let name = name(of: result)
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
                    self.wantsConnection = false
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
        guard wantsConnection else { showFound(); return }
        if let found {
            status = .connecting(name(of: found))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.wantsConnection, self.connection == nil, let found = self.found else { return }
                self.open(found)
            }
        } else {
            status = .searching
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
