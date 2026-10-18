import Foundation

public enum BridgeStartupError: LocalizedError {
    case pythonMissing(URL)
    case scriptMissing(URL)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .pythonMissing(let url):
            return "Interpréteur Python introuvable à l'emplacement \(url.path)"
        case .scriptMissing(let url):
            return "Pont introuvable à l'emplacement \(url.path)"
        case .launchFailed(let message):
            return "Le pont n'a pas pu démarrer : \(message)"
        }
    }
}

/// Runs the Python bridge and turns its stdout into a stream of events.
///
/// stdout is the protocol channel and is parsed line by line; stderr is appended to
/// a log file, since the core writes diagnostics there.
public final class BridgeProcess: @unchecked Sendable {
    private let process = Process()
    private let inPipe = Pipe()
    private let outPipe = Pipe()
    private let errPipe = Pipe()

    private let lock = NSLock()
    private var buffer = Data()
    private var continuation: AsyncStream<BridgeEvent>.Continuation?

    public private(set) var logURL: URL?

    public init() {}

    public var isRunning: Bool { process.isRunning }

    public func start(
        python: URL,
        script: URL,
        logDirectory: URL,
        environment: [String: String] = [:]
    ) throws -> AsyncStream<BridgeEvent> {
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw BridgeStartupError.pythonMissing(python)
        }
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw BridgeStartupError.scriptMissing(script)
        }

        process.executableURL = python
        process.arguments = [script.path]
        // Le bundle désigne ici son binaire katago, ses modèles et sa configuration.
        // Vide en développement, où le pont lit ~/.katrain comme avant.
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.currentDirectoryURL = script.deletingLastPathComponent()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        let (stream, continuation) = AsyncStream<BridgeEvent>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.ingest(handle.availableData)
        }
        startLogging(to: logDirectory)

        process.terminationHandler = { [weak self] _ in
            self?.outPipe.fileHandleForReading.readabilityHandler = nil
            self?.errPipe.fileHandleForReading.readabilityHandler = nil
            self?.continuation?.finish()
        }

        do {
            try process.run()
        } catch {
            continuation.finish()
            throw BridgeStartupError.launchFailed(error.localizedDescription)
        }
        return stream
    }

    private func startLogging(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("bridge.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        logURL = url
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        errPipe.fileHandleForReading.readabilityHandler = { chunk in
            let data = chunk.availableData
            guard !data.isEmpty else { return }
            try? handle.write(contentsOf: data)
        }
    }

    /// Accumulates bytes and emits one event per complete line.
    private func ingest(_ chunk: Data) {
        guard !chunk.isEmpty else {
            continuation?.finish()
            return
        }
        var lines: [String] = []
        lock.lock()
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        lock.unlock()

        for line in lines {
            guard let event = try? BridgeEvent.decode(line: line) else {
                FileHandle.standardError.write(Data("undecodable bridge line: \(line)\n".utf8))
                continue
            }
            continuation?.yield(event)
        }
    }

    /// Sees every command on its way out; the tests listen here, with no bridge running.
    var onSend: ((BridgeCommand) -> Void)?

    public func send(_ command: BridgeCommand) {
        onSend?(command)
        guard process.isRunning, let data = try? command.encodedLine() else { return }
        try? inPipe.fileHandleForWriting.write(contentsOf: data)
    }

    /// Asks the bridge to quit, then makes sure it does.
    public func stop() {
        guard process.isRunning else { return }
        send(.quit(id: -1))
        try? inPipe.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [process] in
            if process.isRunning { process.terminate() }
        }
    }
}
