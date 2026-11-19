import Darwin
import Foundation
import Testing

@testable import MoyoCore

/// A bridge that dies between `isRunning` and the write must not take the app down
/// with SIGPIPE: the write fails, and the stream's end says the bridge stopped.
@Suite("Écriture vers le pont")
struct BridgePipeTests {
    @Test("Écrire dans le tube d'un pont mort ne lève pas SIGPIPE")
    func noSigpipe() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("bridge.sh")
        try Data("exit 0\n".utf8).write(to: script)

        let bridge = BridgeProcess()
        _ = try bridge.start(python: URL(fileURLWithPath: "/bin/sh"), script: script, logDirectory: directory)
        #expect(fcntl(bridge.commandDescriptor, F_GETNOSIGPIPE) == 1)
    }
}
