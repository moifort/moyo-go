import Foundation

/// Holds the last state the bridge sent and forwards the player's intentions to it.
///
/// Nothing here decides whether a move is legal, whose turn it is, or what the score
/// is. Every one of those answers arrives as an event.
@MainActor
@Observable
public final class GameSession {
    public enum Phase: Equatable {
        case starting
        case running
        case failed(String)
    }

    /// What the player chose last, carried across launches.
    ///
    /// These are preferences, not state: at startup they are sent to the bridge,
    /// which then owns the truth. Each mode keeps its own setting, so switching from
    /// the human model to a period style and back finds the rank where it was left.
    public struct Settings: Equatable, Sendable, Codable {
        public var size: Int
        public var komi: Double
        public var rules: String
        public var humanColor: PlayerColor
        public var aiStrategy: String
        public var aiSettingValues: [String: Double]

        public init(
            size: Int = 19,
            komi: Double = 6.5,
            rules: String = "japanese",
            humanColor: PlayerColor = .black,
            aiStrategy: String = "ai:human",
            aiSettingValues: [String: Double] = [:]
        ) {
            self.size = size
            self.komi = komi
            self.rules = rules
            self.humanColor = humanColor
            self.aiStrategy = aiStrategy
            self.aiSettingValues = aiSettingValues
        }

        public func value(for mode: AIMode) -> Double? {
            aiSettingValues[mode.id]
        }

        public mutating func setValue(_ value: Double, for mode: AIMode) {
            aiSettingValues[mode.id] = value
        }
    }

    public private(set) var phase: Phase = .starting
    public private(set) var state: GameState?
    public private(set) var engineDescription: String?
    public private(set) var lastErrorMessage: String?
    public var settings = Settings()

    /// AI modes this installation offers, in KaTrain's own recommended order.
    public private(set) var availableStrategies: [String] = []
    /// Current settings per mode, as the bridge reports them at startup.
    public private(set) var bridgeSettings: [String: [String: SettingValue]] = [:]

    public var modes: [AIMode] { availableStrategies.map(AIMode.mode(for:)) }

    /// The mode actually in force, taken from the last state rather than from our
    /// own settings, so the interface reflects the bridge and not the reverse.
    public var currentMode: AIMode {
        AIMode.mode(for: state?.aiStrategy ?? settings.aiStrategy)
    }

    /// Value of a mode's main setting: what the bridge last reported, else the
    /// startup value, else the middle of the control's range.
    public func settingValue(for mode: AIMode) -> Double? {
        guard let setting = mode.setting else { return nil }
        if state?.aiStrategy == mode.id, let value = state?.aiSettings?[setting.key]?.doubleValue {
            return value
        }
        if let remembered = settings.value(for: mode) {
            return remembered
        }
        if let value = bridgeSettings[mode.id]?[setting.key]?.doubleValue {
            return value
        }
        return (setting.range.lowerBound + setting.range.upperBound) / 2
    }

    /// Switches the opponent mid-game; it applies from its next move.
    public func setAI(mode: AIMode, value: Double?) {
        settings.aiStrategy = mode.id
        var payload: [String: Double] = [:]
        if let setting = mode.setting, let value {
            payload[setting.key] = value
            settings.setValue(value, for: mode)
        }
        store.save(settings)
        bridge.send(.setAI(id: nextID(), strategy: mode.id, settings: payload))
    }

    public let thinking = ThinkingIndicator()

    /// The phone watching the real board, when the player has connected one.
    public let phone = PhoneLink()
    /// The move sent on the phone's behalf and not yet answered by the bridge,
    /// so the same stone is not played twice while the state is in flight.
    private var phoneMoveInFlight: Point?

    /// Score lead per move number, filled in as analyses come back.
    public private(set) var scoreByMove: [Int: Double] = [:]

    /// How far KataGo has got through a record under review, nil when it is done
    /// or when no record is open.
    public private(set) var analysisProgress: (done: Int, total: Int)?

    /// The record's file name, for the window title.
    public private(set) var recordName: String?

    /// A record that arrived before the engine was ready, read while its sandbox
    /// grant was live and held until the bridge can take it.
    private var recordWaiting: SGFImport.Record?

    var hasRecordWaiting: Bool { recordWaiting != nil }

    /// A game the bridge has turned into text, waiting for the save panel.
    public private(set) var pendingExport: SGFExport.Document?

    private let bridge: BridgeProcess
    private let store: SettingsStore
    private var nextCommandID = 1
    private var hasStarted = false
    private var eventTask: Task<Void, Never>?

    public init(bridge: BridgeProcess = BridgeProcess(), store: SettingsStore = SettingsStore()) {
        self.bridge = bridge
        self.store = store
        self.settings = store.load() ?? Settings()
        phone.onBoard = { [weak self] board in self?.phoneBoardDidChange(board) }
    }

    // -- lifecycle -----------------------------------------------------------

    /// Starts the bridge once. Later calls do nothing, so a view coming back up
    /// never launches a second KataGo.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard let location = BridgeLocation.resolve() else {
            phase = .failed(
                "Emplacement du projet inconnu. Définissez MOYO_DEV_ROOT ou reconstruisez l'application."
            )
            return
        }
        do {
            let events = try bridge.start(
                python: location.python,
                script: location.script,
                logDirectory: location.logDirectory,
                environment: location.environment
            )
            eventTask = Task { [weak self] in
                for await event in events {
                    self?.handle(event)
                }
                self?.bridgeDidStop()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func stop() {
        eventTask?.cancel()
        bridge.stop()
    }

    private func bridgeDidStop() {
        guard case .failed = phase else {
            phase = .failed("Le pont s'est arrêté. La partie en cours est perdue.")
            return
        }
    }

    // -- events --------------------------------------------------------------

    /// Internal rather than private so the tests can play the bridge's part.
    func handle(_ event: BridgeEvent) {
        switch event {
        case .ready(let katago, let model, let strategies, let settings):
            phase = .running
            engineDescription = model.map { URL(fileURLWithPath: $0).lastPathComponent } ?? katago
            availableStrategies = strategies
            bridgeSettings = settings
            // A record double-clicked in the Finder launched the app: it is what the
            // player came for, so it takes the place of the opening game.
            if let record = recordWaiting {
                recordWaiting = nil
                load(record)
            } else {
                newGame()
            }

        case .state(_, let newState):
            apply(newState)

        case .thinking(let value):
            value ? thinking.began() : thinking.ended()

        case .score(let moveNumber, let scoreLead):
            scoreByMove[moveNumber] = scoreLead

        case .analysisProgress(let done, let total):
            analysisProgress = done >= total ? nil : (done, total)

        case .sgf(_, let contents):
            pendingExport = SGFExport.Document(
                name: SGFExport.suggestedName(recordName: isReviewing ? recordName : nil, date: .now),
                contents: contents
            )

        case .failure(_, let code, let message):
            // Some refusals are answers, not faults, and a keystroke that arrives a
            // moment too early should not raise a dialog: an illegal move simply
            // does not land, and a variation asked for before its analysis has come
            // back simply does not move.
            if !Self.silentFailures.contains(code) {
                lastErrorMessage = message
            }

        case .engineFailed(let message):
            phase = .failed(message)

        case .unknown:
            break
        }
    }

    /// Refusals the board answers on its own, without a word.
    private static let silentFailures: Set<String> = ["illegal_move", "no_variation"]

    private func apply(_ newState: GameState) {
        // Moves beyond the current one no longer exist, typically after an undo —
        // but a record under review has a future as well as a past, and stepping
        // back through it must not rub out the part of the chart that lies ahead.
        if !newState.isReviewing {
            scoreByMove = scoreByMove.filter { $0.key <= newState.moveNumber }
        }
        for (index, score) in newState.scoreHistory.enumerated() {
            if let score { scoreByMove[index] = score }
        }
        state = newState
        if newState.status != .playing { thinking.ended() }
        phoneMoveInFlight = nil
        syncWithPhone()
    }

    // -- phone ----------------------------------------------------------------

    /// The real board changed. A phone that records a game of its own is followed;
    /// otherwise a board of another size starts a matching game, and any other board
    /// is compared with the game to find the player's move.
    private func phoneBoardDidChange(_ board: PhoneBoard) {
        if board.follow {
            follow(board)
            return
        }
        guard phase == .running else { return }
        if state == nil || state?.size != board.size, board.stones.isEmpty {
            settings.size = board.size
            newGame()
            return
        }
        syncWithPhone()
    }

    /// The board followed on the phone, last loaded into the bridge.
    private var followedBoard: PhoneBoard?

    /// True while the window shows the board of a phone that records its own game.
    public var isFollowingPhone: Bool { followedBoard != nil }

    /// Shows the phone's board in place of whatever the window had open — a game
    /// against the AI, a record, an earlier position of the same game. Only stones
    /// reach the Mac, so it opens as a record of that one position, which KataGo reads.
    private func follow(_ board: PhoneBoard) {
        guard board != followedBoard else { return }
        let name: String
        switch phone.status {
        case .connected(let phoneName), .connecting(let phoneName): name = phoneName
        default: name = "Téléphone"
        }
        let contents = PhoneRecord.sgf(board, komi: settings.komi, event: "En direct — \(name)")
        load(SGFImport.Record(name: name, contents: contents))
        followedBoard = board
    }

    private func syncWithPhone() {
        guard let board = phone.latest, let state, canAct,
              let point = BoardSync.pendingMove(phone: board, game: state),
              point != phoneMoveInFlight else { return }
        phoneMoveInFlight = point
        play(row: point.row, col: point.col)
    }

    // -- commands ------------------------------------------------------------

    private func nextID() -> Int {
        defer { nextCommandID += 1 }
        return nextCommandID
    }

    public func newGame() {
        followedBoard = nil
        store.save(settings)
        scoreByMove.removeAll()
        state = nil
        lastErrorMessage = nil
        recordName = nil
        analysisProgress = nil
        bridge.send(
            .newGame(
                id: nextID(),
                size: settings.size,
                komi: settings.komi,
                rules: settings.rules,
                humanColor: settings.humanColor,
                aiStrategy: settings.aiStrategy,
                aiSettings: newGameSettings
            )
        )
    }

    /// The main setting of the chosen mode, if it has one. Everything else keeps the
    /// values from the shared KaTrain configuration.
    private var newGameSettings: [String: Double] {
        let mode = AIMode.mode(for: settings.aiStrategy)
        guard let setting = mode.setting, let value = settingValue(for: mode) else { return [:] }
        return [setting.key: value]
    }

    public func play(row: Int, col: Int) {
        guard canAct else { return }
        bridge.send(.play(id: nextID(), row: row, col: col))
    }

    public func passTurn() {
        guard canAct else { return }
        bridge.send(.pass(id: nextID()))
    }

    /// Flips the group under a point between dead and alive, while counting.
    public func toggleDead(row: Int, col: Int) {
        guard state?.status == .scoring else { return }
        bridge.send(.toggleDead(id: nextID(), row: row, col: col))
    }

    public func acceptScore() {
        guard state?.status == .scoring else { return }
        bridge.send(.acceptScore(id: nextID()))
    }

    /// Takes back the last pass and carries on playing.
    public func resumeGame() {
        guard state?.status == .scoring else { return }
        bridge.send(.resumeGame(id: nextID()))
    }

    public func undo() {
        guard state != nil, state?.status == .playing else { return }
        bridge.send(.undo(id: nextID()))
    }

    public func resign() {
        guard state != nil, state?.status == .playing else { return }
        bridge.send(.resign(id: nextID()))
    }

    /// Dismisses the last failure, once the player has seen it.
    public func clearError() {
        lastErrorMessage = nil
    }

    // -- review --------------------------------------------------------------

    /// True once a record is open and being read.
    public var isReviewing: Bool { state?.isReviewing ?? false }

    /// Opens a record, replacing whatever the window was showing.
    ///
    /// The file is read here and sent as text: the bridge opens nothing, which keeps
    /// the sandbox out of the child process and the encoding guess in AppKit's hands.
    public func openRecord(at url: URL) {
        followedBoard = nil
        do {
            load(try SGFImport.read(url))
        } catch {
            recordName = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Hands a record to the bridge, or holds it until the bridge is ready for one.
    private func load(_ record: SGFImport.Record) {
        scoreByMove.removeAll()
        analysisProgress = nil
        lastErrorMessage = nil
        recordName = record.name
        thinking.ended()
        guard phase == .running else {
            recordWaiting = record
            return
        }
        bridge.send(.loadSGF(id: nextID(), name: record.name, contents: record.contents))
    }

    /// True when there is a game or a record to save.
    public var canExport: Bool { phase == .running && state != nil }

    /// Asks the bridge for the game as SGF; the answer lands in `pendingExport`.
    ///
    /// A game against the AI is signed with the Mac user's name and the opponent's
    /// mode. A record under review keeps the names it came with.
    public func exportRecord() {
        guard canExport else { return }
        var black: String?
        var white: String?
        if !isReviewing, let state {
            let mode = currentMode
            let players = SGFExport.players(
                humanColor: state.humanColor,
                human: NSFullUserName(),
                ai: SGFExport.aiName(mode: mode, value: settingValue(for: mode))
            )
            (black, white) = (players.black, players.white)
        }
        bridge.send(.exportSGF(id: nextID(), blackName: black, whiteName: white))
    }

    /// The save panel is done with the document, written or not.
    public func exportHandled() {
        pendingExport = nil
    }

    /// Moves to a position in the record. The bridge clamps anything out of range.
    public func goto(moveNumber: Int) {
        guard isReviewing else { return }
        bridge.send(.goto(id: nextID(), moveNumber: moveNumber))
    }

    /// One move back or forward along the record.
    public func step(_ delta: Int) {
        guard let state, state.isReviewing else { return }
        // Inside a variation, a plain arrow leaves it first: the bridge prunes the
        // branch and lands on the record's own position.
        goto(moveNumber: state.moveNumber + delta)
    }

    /// One move of a continuation, added or taken back: KataGo's own, or the local one.
    public func stepVariation(_ delta: Int, kind: VariationKind = .best) {
        guard isReviewing else { return }
        bridge.send(.variation(id: nextID(), step: delta > 0 ? 1 : -1, kind: kind))
    }

    /// Option is held down. The local layer — zone, blue disc, loader — shows only
    /// then, or while its sequence is walked: by default the board shows the best
    /// move alone. The first press of a position asks KataGo to read it.
    public var isOptionHeld = false {
        didSet {
            guard isOptionHeld, !oldValue, let state, state.isReviewing, state.localZone != nil else { return }
            bridge.send(.readLocal(id: nextID()))
        }
    }

    /// Whether the board shows the local reading right now.
    public var showsLocalReading: Bool {
        guard let state, state.isReviewing else { return false }
        return isOptionHeld || state.variationKind == .local || state.localWanted == true
    }

    /// Reads the fight inside a zone drawn on the board, until it is cleared.
    public func drawLocalZone(_ zone: LocalZone) {
        guard isReviewing else { return }
        bridge.send(.setLocalZone(id: nextID(), zone: zone))
    }

    /// Hands the zone back to the bridge, which infers it around the last move.
    public func clearDrawnZone() {
        guard hasDrawnZone else { return }
        bridge.send(.setLocalZone(id: nextID(), zone: nil))
    }

    public var hasDrawnZone: Bool {
        isReviewing && state?.localZoneDrawn == true
    }

    /// Whether the local sequence can be started or walked further.
    public var canWalkLocal: Bool {
        guard let state, state.isReviewing else { return false }
        return state.localZone != nil
    }

    /// Whether a local sequence is under way, so it can be taken back.
    public var isWalkingLocal: Bool {
        state?.variationKind == .local && (state?.variationDepth ?? 0) > 0
    }

    public var canStepBackward: Bool {
        guard let state, state.isReviewing else { return false }
        return state.moveNumber > 0 || (state.variationDepth ?? 0) > 0
    }

    public var canStepForward: Bool {
        guard let state, state.isReviewing, let count = state.moveCount else { return false }
        return state.moveNumber < count
    }

    /// Scores flipped to the human player's side: positive means they are ahead.
    ///
    /// The bridge reports the lead from Black's point of view, which would make the
    /// colours lie whenever the player takes White.
    public var scoresFromPlayerSide: [Int: Double] {
        let sign: Double = (state?.humanColor ?? .black) == .black ? 1 : -1
        return scoreByMove.mapValues { $0 * sign }
    }

    /// The most recent lead known at or before a given move.
    ///
    /// Analyses arrive a move or two behind the stones. Reading only the current move
    /// would blank the figure out every time the AI plays, so the last known value
    /// holds until a fresher one arrives.
    nonisolated static func latestLead(in scores: [Int: Double], upTo moveNumber: Int) -> Double? {
        scores.keys.filter { $0 <= moveNumber }.max().flatMap { scores[$0] }
    }

    /// The player's current lead, held over while KataGo catches up.
    public var currentLead: Double? {
        guard let state else { return nil }
        let sign: Double = state.humanColor == .black ? 1 : -1
        let lead =
            scoreByMove[state.moveNumber]
            ?? state.scoreLead
            ?? Self.latestLead(in: scoreByMove, upTo: state.moveNumber)
        return lead.map { $0 * sign }
    }

    /// True when the player may act: a game is running and it is their turn.
    ///
    /// `isHumanTurn` is already false under review, so nothing extra is needed here.
    public var canAct: Bool {
        phase == .running && (state?.isHumanTurn ?? false)
    }
}
