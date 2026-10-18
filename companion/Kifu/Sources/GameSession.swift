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
    /// How far, in frame pixels, a precisely placed corner may be nudged onto the grid.
    static let cornerRefineRadius = 8

    var phase: Phase = .calibrating
    var cameraAvailable = true
    var preview: CGImage?
    var frameSize: CGSize = .zero
    /// Full-resolution frame frozen for placing the corners.
    var frozen: CGImage?
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
    var result: GameResult?
    var cancelled = false
    /// Macs running Moyo that follow the game.
    var connectedMacs = 0

    private let worker = DispatchQueue(label: "Kifu.worker", qos: .userInitiated)
    private var camera: CameraSession?
    nonisolated(unsafe) private let engine = Engine()
    nonisolated private let server = BoardServer()

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
        server.onClientsChanged = { [weak self] count in
            Task { @MainActor in self?.connectedMacs = count }
        }
        server.start()
    }

    func stopCamera() {
        camera?.stop()
        server.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func cancel() { cancelled = true }

    // MARK: Calibration

    /// Freezes the next frame at full resolution so that corners can be placed on it zoomed in.
    func freeze() {
        taps = []
        calibration = nil
        calibrationFailed = false
        gridPoints = []
        worker.async { self.engine.reader = nil }
        camera?.requestFullFrame()
    }

    func unfreeze() {
        frozen = nil
        taps = []
        calibration = nil
        gridPoints = []
        worker.async { self.engine.reader = nil; self.engine.frozenGray = nil }
    }

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
            guard let gray = self.engine.frozenGray ?? self.engine.latest?.gray,
                  BoardGeometry(calibration: Calibration(lines: Self.lines, corners: taps)) != nil else {
                Task { @MainActor in self.taps = []; self.calibrationFailed = true }
                return
            }
            // Corners are placed precisely, zoomed in: only nudge them onto the line crossings.
            let corners = BoardGeometry.fitCorners(taps, lines: Self.lines, in: gray, radius: Self.cornerRefineRadius)
            CalibrationDump.save(frame: gray, taps: taps, corners: corners)
            let calibration = Calibration(lines: Self.lines, corners: corners)
            guard let geometry = BoardGeometry(calibration: calibration) else {
                Task { @MainActor in self.taps = []; self.calibrationFailed = true }
                return
            }
            self.engine.reader = IntersectionReader(geometry: geometry)
            self.engine.calibration = calibration
            let points = (0..<Self.lines).map { row in
                (0..<Self.lines).map { col in geometry.imagePoint(of: Intersection(col: col, row: row)) }
            }
            Task { @MainActor in
                self.calibration = calibration
                self.gridPoints = points
                self.minSpacing = geometry.minSpacing
                self.frozen = nil
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
        let trial = TrialLog.enabled ? TrialLog(date: date) : nil
        worker.async {
            guard let reader = self.engine.reader else { return }
            let start = self.engine.lastReadPosition
            self.engine.recorder = Recorder(reader: reader, start: start, date: date)
            self.engine.fileURL = url
            self.engine.recording = true
            self.engine.trial = trial
            self.writeFile()
            self.logTrial([.start])
            self.publishRecorder()
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
            self.logTrial([.accepted])
            self.publishRecorder()
        }
    }

    /// Back to the corners, keeping the game.
    func recalibrate() {
        taps = []
        calibration = nil
        gridPoints = []
        frozen = nil
        camera?.unlockForCalibration()
        phase = .calibrating
        worker.async { self.engine.reader = nil; self.engine.recording = false; self.engine.frozenGray = nil }
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

    func endGame(_ result: GameResult) {
        self.result = result
        worker.async {
            self.engine.recording = false
            self.engine.result = result
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
        var frozenGray: GrayImage?
        var recording = false
        var fileURL: URL?
        var calibration: Calibration?
        var trial: TrialLog?
        var result: GameResult?
    }

    private nonisolated func handle(_ frame: CameraFrame) {
        worker.async { [self] in
            engine.latest = frame
            if frame.full != nil { engine.frozenGray = frame.gray }
            let size = CGSize(width: frame.gray.width, height: frame.gray.height)
            Task { @MainActor in
                self.preview = frame.preview
                self.frameSize = size
                if let full = frame.full { self.frozen = full }
            }
            if var recorder = engine.recorder, engine.reader != nil, engine.recording {
                let before = recorder.status
                let update = recorder.process(frame.gray, at: frame.time)
                engine.recorder = recorder
                if !update.moves.isEmpty || update.takenBack > 0 { writeFile() }
                let alert = update.status == .lost && before != .lost
                if alert {
                    Task { @MainActor in UINotificationFeedbackGenerator().notificationOccurred(.warning) }
                }
                if let trial = engine.trial {
                    var reasons: [TrialLog.Reason] = []
                    if !update.moves.isEmpty { reasons.append(.move) }
                    if update.takenBack > 0 { reasons.append(.takeBack) }
                    if alert { reasons.append(.alert) }
                    if reasons.isEmpty, trial.isDue(at: frame.time) { reasons.append(.periodic) }
                    if !reasons.isEmpty { logTrial(reasons, frame: frame) }
                }
                publishRecorder()
            } else if let reader = engine.reader {
                let readings = reader.read(frame.gray, previous: engine.lastReadPosition)
                engine.lastReadPosition = readings.position
                Task { @MainActor in self.readPosition = readings.position }
            }
        }
    }

    /// Trial mode only: saves `frame` (the latest one by default) with the recorder's view of it.
    private nonisolated func logTrial(_ reasons: [TrialLog.Reason], frame: CameraFrame? = nil) {
        guard let trial = engine.trial, let recorder = engine.recorder,
              let frame = frame ?? engine.latest else { return }
        trial.save(frame: frame.gray, time: frame.time, reasons: reasons,
                   calibration: engine.calibration, recorder: recorder)
    }

    private nonisolated func publishRecorder() {
        guard let recorder = engine.recorder else { return }
        let accepted = recorder.record.position
        let candidate = recorder.candidate
        let status = recorder.status
        let count = recorder.record.moves.count
        let last = recorder.record.moves.last?.move
        server.publish(position: accepted, status: status)
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
        let text = SGFWriter.write(recorder.record, result: engine.result)
        guard let url = engine.fileURL else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func newFileURL(for date: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd HH'h'mm"
        return documents.appendingPathComponent("Partie \(f.string(from: date)).sgf")
    }
}
