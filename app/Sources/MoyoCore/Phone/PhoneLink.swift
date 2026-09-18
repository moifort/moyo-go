import Foundation
import Network
import Observation

/// Finds the phone on the local network over Bonjour and streams the board it sees.
///
/// The phone runs GoBoardVision, which advertises `_goboard._tcp` and writes one
/// JSON line per board change. This class owns nothing about the game: it hands
/// each decoded board to `onBoard` and reports its own state for the sidebar.
@Observable
@MainActor
public final class PhoneLink {
    public enum Status: Equatable {
        case idle
        case searching
        case connecting(String)
        case connected(String)
        case failed(String)
    }

    public static let serviceType = "_goboard._tcp"

    public private(set) var status: Status = .idle
    public private(set) var latest: PhoneBoard?
    public var onBoard: ((PhoneBoard) -> Void)?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "Moyo.phone")

    public init() {}

    public var isActive: Bool { status != .idle }

    public func connect() {
        disconnect()
        status = .searching
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                if case .failed(let error) = state { self?.status = .failed(error.localizedDescription) }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let result = results.first else { return }
            Task { @MainActor [weak self] in self?.open(result) }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    public func disconnect() {
        browser?.cancel(); browser = nil
        connection?.cancel(); connection = nil
        buffer.removeAll()
        latest = nil
        status = .idle
    }

    private func open(_ result: NWBrowser.Result) {
        guard connection == nil else { return }
        let name: String
        if case .service(let serviceName, _, _, _) = result.endpoint { name = serviceName } else { name = "iPhone" }
        status = .connecting(name)
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready: self.status = .connected(name); self.receive()
                case .failed(let error): self.status = .failed(error.localizedDescription); self.connection = nil
                case .cancelled: if self.status != .idle { self.status = .searching }; self.connection = nil
                default: break
                }
            }
        }
        self.connection = connection
        connection.start(queue: queue)
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
            }
        }
    }
}
