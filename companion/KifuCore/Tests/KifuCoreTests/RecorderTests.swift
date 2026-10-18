import XCTest
@testable import KifuCore

/// Replays scripted readings instead of reading images.
final class ScriptedReader: BoardReader {
    var queue: [Readings] = []
    func read(_ image: GrayImage, previous: Position?) -> Readings { queue.removeFirst() }
}

final class RecorderTests: XCTestCase {
    private func at(_ col: Int, _ row: Int) -> Intersection { Intersection(col: col, row: row) }
    private let blank = GrayImage(width: 1, height: 1)

    private func position(_ stones: [Intersection: Stone], size: Int = 9) -> Position {
        var p = Position(size: size)
        for (i, s) in stones { p[i] = s }
        return p
    }

    private func make(start: Position = Position(size: 9), required: Int = 3) -> (Recorder, ScriptedReader) {
        let reader = ScriptedReader()
        var settings = RecorderSettings()
        settings.requiredFrames = required
        settings.lostAfter = 8
        return (Recorder(reader: reader, start: start, settings: settings), reader)
    }

    func testStoneIsRecordedOnceStable() {
        var (rec, reader) = make()
        let seen = Readings(position: position([at(4, 4): .black]))
        reader.queue = [seen, seen, seen]
        XCTAssertTrue(rec.process(blank, at: 0).moves.isEmpty)
        XCTAssertTrue(rec.process(blank, at: 0.5).moves.isEmpty)
        let update = rec.process(blank, at: 1.0)
        XCTAssertEqual(update.moves, [Move(color: .black, point: at(4, 4))])
        XCTAssertEqual(update.status, .inSync)
        XCTAssertEqual(rec.record.moves.count, 1)
    }

    func testLastReadingsKeepTheRawImageReading() {
        var (rec, reader) = make()
        let seen = Readings(position: position([at(4, 4): .black]), unreadable: [at(2, 2)])
        reader.queue = [seen]
        XCTAssertNil(rec.lastReadings)
        _ = rec.process(blank, at: 0)
        XCTAssertEqual(rec.lastReadings, seen)
        XCTAssertEqual(rec.candidate, Position(size: 9))
    }

    func testTwoStonesOfDifferentColoursAreRecordedInOrder() {
        var (rec, reader) = make()
        let seen = Readings(position: position([at(4, 4): .black, at(2, 2): .white]))
        reader.queue = [seen, seen, seen]
        _ = rec.process(blank, at: 0); _ = rec.process(blank, at: 0.5)
        XCTAssertEqual(rec.process(blank, at: 1).moves,
                       [Move(color: .black, point: at(4, 4)), Move(color: .white, point: at(2, 2))])
    }

    func testBriefHandIsIgnored() {
        var (rec, reader) = make()
        let hand = Readings(position: position([at(3, 3): .black, at(4, 3): .black, at(5, 3): .black, at(4, 4): .black]))
        let clear = Readings(position: Position(size: 9))
        reader.queue = [hand, hand, clear, clear, clear]
        for t in stride(from: 0.0, through: 2.0, by: 0.5) { _ = rec.process(blank, at: t) }
        XCTAssertTrue(rec.record.moves.isEmpty)
        XCTAssertEqual(rec.status, .inSync)
    }

    func testUnexplainedStablePositionBecomesLostAfterDelayAndResumes() {
        var (rec, reader) = make()
        let hand = Readings(position: position([at(3, 3): .black, at(4, 3): .black, at(5, 3): .black]))
        reader.queue = [Readings](repeating: hand, count: 20) + [Readings](repeating: Readings(position: Position(size: 9)), count: 3)
        var statuses: [Recorder.Status] = []
        for k in 0..<20 { statuses.append(rec.process(blank, at: Double(k) * 0.5).status) }
        XCTAssertEqual(statuses[0], .inSync)
        XCTAssertEqual(statuses[2], .pending)             // stable after 3 frames, unexplained
        XCTAssertEqual(statuses[10], .pending)            // 4 s later, still waiting
        XCTAssertEqual(statuses[19], .lost)               // > 8 s after it became stable
        XCTAssertTrue(rec.record.moves.isEmpty)
        for k in 20..<23 { _ = rec.process(blank, at: Double(k) * 0.5) }
        XCTAssertEqual(rec.status, .inSync)
    }

    func testCaptureWaitsForTheStonesToBeRemoved() {
        let start = Position(parsing: """
        .X.......
        XOX......
        .........
        .........
        .........
        .........
        .........
        .........
        .........
        """)
        var (rec, reader) = make(start: start)
        XCTAssertEqual(rec.record.toPlay, .black)
        var placed = start; placed[at(1, 2)] = .black
        var removed = placed; removed[at(1, 1)] = .empty
        reader.queue = [Readings](repeating: Readings(position: placed), count: 6) + [Readings](repeating: Readings(position: removed), count: 3)
        var statuses: [Recorder.Status] = []
        for k in 0..<9 { statuses.append(rec.process(blank, at: Double(k) * 0.5).status) }
        XCTAssertEqual(statuses[2], .awaitingCaptureRemoval)
        XCTAssertEqual(statuses[5], .awaitingCaptureRemoval)
        XCTAssertEqual(statuses[8], .inSync)
        XCTAssertEqual(rec.record.moves.map(\.move), [Move(color: .black, point: at(1, 2))])
        XCTAssertEqual(rec.record.position, removed)
    }

    func testTakebackRemovesTheMove() {
        var (rec, reader) = make()
        let one = Readings(position: position([at(4, 4): .black]))
        let none = Readings(position: Position(size: 9))
        reader.queue = [one, one, one, none, none, none]
        for k in 0..<3 { _ = rec.process(blank, at: Double(k) * 0.5) }
        XCTAssertEqual(rec.record.moves.count, 1)
        var update = Recorder.Update()
        for k in 3..<6 { update = rec.process(blank, at: Double(k) * 0.5) }
        XCTAssertEqual(update.takenBack, 1)
        XCTAssertTrue(rec.record.moves.isEmpty)
        XCTAssertEqual(update.status, .inSync)
    }

    func testAcceptForcesTheCandidateIntoTheRecord() {
        var (rec, reader) = make()
        let two = Readings(position: position([at(3, 3): .black, at(5, 5): .black]))
        reader.queue = [two, two, two]
        for k in 0..<3 { _ = rec.process(blank, at: Double(k) * 0.5) }
        XCTAssertEqual(rec.status, .pending)
        rec.accept()
        XCTAssertEqual(rec.status, .inSync)
        XCTAssertEqual(rec.record.moves.count, 2)
        XCTAssertTrue(rec.record.moves.allSatisfy(\.uncertain))
    }

    func testRecalibrationKeepsTheRecord() {
        var (rec, reader) = make()
        let one = Readings(position: position([at(4, 4): .black]))
        reader.queue = [one, one, one, one]
        for k in 0..<3 { _ = rec.process(blank, at: Double(k) * 0.5) }
        rec.recalibrate(reader: reader)
        XCTAssertEqual(rec.record.moves.count, 1)
        XCTAssertEqual(rec.process(blank, at: 2).status, .inSync)
    }

    func testEndToEndOnRenderedFrames() {
        var scene = SyntheticScene(width: 600, height: 450)
        let geometry = BoardGeometry(calibration: scene.calibration)!
        let reader = IntersectionReader(geometry: geometry)
        var settings = RecorderSettings(); settings.requiredFrames = 2
        var rec = Recorder(reader: reader, start: Position(size: 19), settings: settings)
        scene.stones = [at(3, 3): .black]
        let frame1 = scene.render()
        scene.stones[at(15, 15)] = .white
        let frame2 = scene.render()
        _ = rec.process(frame1, at: 0)
        XCTAssertEqual(rec.process(frame1, at: 0.5).moves, [Move(color: .black, point: at(3, 3))])
        _ = rec.process(frame2, at: 1)
        XCTAssertEqual(rec.process(frame2, at: 1.5).moves, [Move(color: .white, point: at(15, 15))])
        XCTAssertTrue(SGFWriter.write(rec.record).hasSuffix(";B[dd];W[pp])"))
    }
}
