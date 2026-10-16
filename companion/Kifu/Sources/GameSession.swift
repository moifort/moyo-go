import Foundation
import CoreGraphics
import Observation
import KifuCore
import UIKit

/// Drives one game: calibration, recording, file writing. UI state lives on the main actor,
/// the vision work runs on a serial worker queue.
@Observable
@MainActor
final class GameSession {
    enum Phase { case calibrating, recording, finished }

    nonisolated static let lines = 19
    static let minimumComfortableSpacing = 12.0

    var phase: Phase = .calibrating
    var cameraAvailable = true
    var preview: CGImage?
    var frameSize: CGSize = .zero
    /// Corners tapped so far, in full-resolution frame pixels.
    var taps: [Point] = []
    var calibration: Calibration?
    var calibrationFailed = false
    var gridPoints: [[Point]] = []
    var minSpacing: Double = 0
    var readPosition = Position(size: GameSession.lines)
    var acceptedPosition = Position(size: GameSession.lines)
    var candidatePosition = Position(size: GameSession.lines)
    var status: Recorder.Status = .inSync
    var moveCount = 0
    var lastMove: Move?
    var fileURL: URL?
    var startedAt: Date?
    var cancelled = false

    private let worker = DispatchQueue(label: "Kifu.worker", qos: .userInitiated)
    private var camera: CameraSession?
    nonisolated(unsafe) private let engine = Engine()

    var isCalibrated: Bool { calibration != nil }
    var qualityWarning: String? {
        guard isCalibrated else { return nil }
        return minSpacing < Self.minimumComfortableSpacing
            ? "Monte un peu le téléphone, les rangées du fond sont trop serrées." : nil
    }

    func startCamera() async {
        let camera = CameraSession { [weak self] frame in self?.handle(frame) }
        self.camera = camera
        cameraAvailable = await camera.start()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopCamera() {
        camera?.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func cancel() { cancelled = true }

    // MARK: Calibration

    func addTap(_ point: Point) {
        guard taps.count < 4 else { return }
        calibrationFailed = false
        taps.append(point)
        if taps.count == 4 { fitCalibration(from: taps) }
    }

    func clearTaps() {
        taps = []
        calibration = nil
        gridPoints = []
        worker.async { self.engine.reader = nil }
    }

    private func fitCalibration(from taps: [Point]) {
        worker.async {
            guard let gray = self.engine.latest?.gray, BoardGeometry(calibration: Calibration(lines: Self.lines, corners: taps)) != nil else {
                Task { @MainActor in self.taps = []; self.calibrationFailed = true }
                return
            }
            // Rough taps give the perspective; the grid itself is found inside that area.
            guard let corners = GridDetector.detect(roughCorners: taps, lines: Self.lines, in: gray) else {
                Task { @MainActor in self.taps = []; self.calibrationFailed = true }
                return
            }
            let calibration = Calibration(lines: Self.lines, corners: corners)
            guard let geometry = BoardGeometry(calibration: calibration) else {
                Task { @MainActor in self.taps = []; self.calibrationFailed = true }
                return
            }
            self.engine.reader = IntersectionReader(geometry: geometry)
            let points = (0..<Self.lines).map { row in
                (0..<Self.lines).map { col in geometry.imagePoint(of: Intersection(col: col, row: row)) }
            }
            Task { @MainActor in
                self.calibration = calibration
                self.gridPoints = points
                self.minSpacing = geometry.minSpacing
            }
        }
    }

    func startGame() {
        guard isCalibrated else { return }
        let date = Date()
        startedAt = date
        fileURL = Self.newFileURL(for: date)
        camera?.lockForGame()
        let url = fileURL
        worker.async {
            guard let reader = self.engine.reader else { return }
            let start = self.engine.lastReadPosition
            self.engine.recorder = Recorder(reader: reader, start: start, date: date)
            self.engine.fileURL = url
            self.engine.recording = true
            self.writeFile()
            Task { @MainActor in
                self.acceptedPosition = start
                self.candidatePosition = start
                self.moveCount = 0
                self.lastMove = nil
                self.status = .inSync
                self.phase = .recording
            }
        }
    }

    // MARK: Recording

    /// "C'est bon": the board as seen becomes the record.
    func acceptCandidate() {
        worker.async {
            self.engine.recorder?.accept()
            self.writeFile()
            self.publishRecorder()
        }
    }

    /// Back to the corners, keeping the game.
    func recalibrate() {
        taps = []
        calibration = nil
        gridPoints = []
        camera?.unlockForCalibration()
        phase = .calibrating
        worker.async { self.engine.reader = nil; self.engine.recording = false }
    }

    /// Resume recording after a recalibration.
    func resumeGame() {
        guard isCalibrated else { return }
        camera?.lockForGame()
        worker.async {
            guard let reader = self.engine.reader else { return }
            self.engine.recorder?.recalibrate(reader: reader)
            self.engine.recording = true
            self.publishRecorder()
            Task { @MainActor in self.phase = .recording }
        }
    }

    func endGame() {
        worker.async {
            self.engine.recording = false
            self.writeFile()
            Task { @MainActor in self.phase = .finished }
        }
    }

    // MARK: Worker side

    private final class Engine {
        var latest: CameraFrame?
        var reader: IntersectionReader?
        var recorder: Recorder?
        var lastReadPosition = Position(size: GameSession.lines)
        var recording = false
        var fileURL: URL?
    }

    private nonisolated func handle(_ frame: CameraFrame) {
        worker.async { [self] in
            engine.latest = frame
            let size = CGSize(width: frame.gray.width, height: frame.gray.height)
            Task { @MainActor in
                self.preview = frame.preview
                self.frameSize = size
            }
            if var recorder = engine.recorder, engine.reader != nil, engine.recording {
                let before = recorder.status
                let update = recorder.process(frame.gray, at: frame.time)
                engine.recorder = recorder
                if !update.moves.isEmpty || update.takenBack > 0 { writeFile() }
                if update.status == .lost, before != .lost {
                    Task { @MainActor in UINotificationFeedbackGenerator().notificationOccurred(.warning) }
                }
                publishRecorder()
            } else if let reader = engine.reader {
                let readings = reader.read(frame.gray, previous: engine.lastReadPosition)
                engine.lastReadPosition = readings.position
                Task { @MainActor in self.readPosition = readings.position }
            }
        }
    }

    private nonisolated func publishRecorder() {
        guard let recorder = engine.recorder else { return }
        let accepted = recorder.record.position
        let candidate = recorder.candidate
        let status = recorder.status
        let count = recorder.record.moves.count
        let last = recorder.record.moves.last?.move
        Task { @MainActor in
            self.acceptedPosition = accepted
            self.candidatePosition = candidate
            self.status = status
            self.moveCount = count
            self.lastMove = last
        }
    }

    private nonisolated func writeFile() {
        guard let recorder = engine.recorder else { return }
        let text = SGFWriter.write(recorder.record)
        guard let url = engine.fileURL else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func newFileURL(for date: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd HH'h'mm"
        return documents.appendingPathComponent("Partie \(f.string(from: date)).sgf")
    }
}
