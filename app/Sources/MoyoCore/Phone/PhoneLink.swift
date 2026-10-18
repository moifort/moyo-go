import dnssd
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

    /// A phone in sight: its Bonjour service, and the name shown for it.
    public struct Phone: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
    }

    public static let serviceType = "_goboard._tcp"

    public private(set) var status: Status = .idle
    /// The phones running Kifu in sight right now, sorted by name.
    public private(set) var phones: [Phone] = []
    public private(set) var latest: PhoneBoard?
    public var onBoard: ((PhoneBoard) -> Void)?
    public var onGameEnd: ((PhoneGameEnd) -> Void)?

    private var browser: NWBrowser?
    /// The phones in sight, by service name.
    private var found: [String: NWBrowser.Result] = [:]
    /// The names read from each phone's host, by service name, once resolved.
    private var hostNames: [String: String] = [:]
    private var resolving: [String: HostResolver] = [:]
    private var connection: NWConnection?
    /// The service of the phone the player chose: a dropped link to it is opened again on its own.
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

    /// The phone's name as its host carries it: iOS hides the name the user gave
    /// the phone from apps like Kifu, which can only advertise "iPhone", but not
    /// from its Bonjour host — "TiPhone-junior.local." reads "TiPhone junior".
    nonisolated static func hostDisplayName(_ host: String) -> String? {
        var name = host.hasSuffix(".") ? String(host.dropLast()) : host
        if name.hasSuffix(".local") { name = String(name.dropLast(".local".count)) }
        name = name.replacingOccurrences(of: "-", with: " ")
        return name.isEmpty ? nil : name
    }

    /// The name shown for the phone behind that service.
    func name(of service: String) -> String {
        hostNames[service] ?? Self.displayName(service)
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

    /// Connects to the phone behind that service, or to the one chosen last.
    public func connect(to service: String? = nil) {
        if let service { chosen = service }
        startDiscovery()
        guard connection == nil, let chosen else { return }
        if let result = found[chosen] {
            open(result, service: chosen)
        } else {
            status = .connecting(name(of: chosen))  // opened as soon as it shows up again
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
        var byService: [String: NWBrowser.Result] = [:]
        for result in results {
            guard case .service(let service, let type, let domain, _) = result.endpoint else { continue }
            byService[service] = result
            if hostNames[service] == nil, resolving[service] == nil {
                resolving[service] = HostResolver(service: service, type: type, domain: domain) { [weak self] host in
                    Task { @MainActor [weak self] in self?.resolved(service, host: host) }
                }
            }
        }
        found = byService
        for service in resolving.keys where byService[service] == nil { resolving[service] = nil }
        listPhones()
        if connection == nil, let chosen, let result = byService[chosen] {
            open(result, service: chosen)
        }
    }

    private func resolved(_ service: String, host: String?) {
        resolving[service] = nil
        guard let host, let name = Self.hostDisplayName(host) else { return }
        hostNames[service] = name
        listPhones()
        switch status {
        case .connecting where chosen == service: status = .connecting(name)
        case .connected where chosen == service: status = .connected(name)
        default: break
        }
    }

    private func listPhones() {
        phones = found.keys.map { Phone(id: $0, name: name(of: $0)) }.sorted { $0.name < $1.name }
    }

    private func open(_ result: NWBrowser.Result, service: String) {
        guard connection == nil else { return }
        status = .connecting(name(of: service))
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self] in
                guard let self, let connection, self.connection === connection else { return }
                switch state {
                case .ready:
                    self.status = .connected(self.name(of: service))
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
        status = .connecting(name(of: chosen))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.connection == nil, self.chosen == chosen, let result = self.found[chosen] else { return }
            self.open(result, service: chosen)
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

/// Resolves one Bonjour service to the host that publishes it, then stops.
/// Released before it answers, it cancels the query.
private final class HostResolver: @unchecked Sendable {
    private var ref: DNSServiceRef?
    private var answer: ((String?) -> Void)?
    private static let queue = DispatchQueue(label: "Moyo.phone.resolve")

    init(service: String, type: String, domain: String, answer: @escaping @Sendable (String?) -> Void) {
        self.answer = answer
        let context = Unmanaged.passUnretained(self).toOpaque()
        let error = DNSServiceResolve(&ref, 0, 0, service, type, domain, { _, _, _, error, _, host, _, _, _, context in
            guard let context else { return }
            let resolver = Unmanaged<HostResolver>.fromOpaque(context).takeUnretainedValue()
            resolver.finish(error == kDNSServiceErr_NoError ? host.map { String(cString: $0) } : nil)
        }, context)
        guard error == kDNSServiceErr_NoError, let ref else { finish(nil); return }
        DNSServiceSetDispatchQueue(ref, Self.queue)
    }

    private func finish(_ host: String?) {
        answer?(host)
        answer = nil
    }

    deinit {
        if let ref { DNSServiceRefDeallocate(ref) }
    }
}
