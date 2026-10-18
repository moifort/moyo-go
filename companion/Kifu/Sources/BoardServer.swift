import Foundation
import UIKit
import Network
import KifuCore

/// Advertises the phone over Bonjour (`_goboard._tcp`, the service Moyo looks for) and sends
/// the accepted position, one JSON line per change, to every connected Mac.
final class BoardServer: @unchecked Sendable {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "Kifu.server")
    private var lastLine: Data?
    /// Called on the server queue with the number of connected Macs.
    var onClientsChanged: ((Int) -> Void)?

    static let viewpointDefaultsKey = "moyoViewpoint"
    /// Whose seat Moyo shows the board from, chosen on the home screen.
    static var viewpoint: BoardBroadcast.Viewpoint {
        UserDefaults.standard.string(forKey: viewpointDefaultsKey).flatMap(BoardBroadcast.Viewpoint.init) ?? .leftPlayer
    }

    func start() {
        queue.async { [self] in
            guard listener == nil, let listener = try? NWListener(using: .tcp) else { return }
            listener.service = NWListener.Service(name: "Kifu — \(UIDevice.current.name)", type: BoardBroadcast.serviceType)
            listener.newConnectionHandler = { [weak self] connection in self?.add(connection) }
            self.listener = listener
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel(); listener = nil
            connections.forEach { $0.cancel() }
            connections.removeAll()
            lastLine = nil
            onClientsChanged?(0)
        }
    }

    /// Sends the position to every Mac, unless it is the line they already have.
    func publish(position: Position, status: Recorder.Status, toPlay: Stone) {
        let data = BoardBroadcast.line(position: position, status: status, toPlay: toPlay, viewpoint: Self.viewpoint)
        queue.async { [self] in
            guard data != lastLine else { return }
            lastLine = data
            for c in connections where c.state == .ready {
                c.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }

    private func add(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                // A newcomer gets the current board straight away.
                if let line = self.lastLine { connection.send(content: line, completion: .contentProcessed { _ in }) }
                self.onClientsChanged?(self.readyCount)
            case .failed:
                connection.cancel()
            case .cancelled:
                self.connections.removeAll { $0 === connection }
                self.onClientsChanged?(self.readyCount)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private var readyCount: Int { connections.filter { $0.state == .ready }.count }
}
