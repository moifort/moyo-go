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
        /// KataGo at work while following a real board. Optional so settings saved
        /// before it existed still load; absent means on.
        public var followAnalysis: Bool?

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

    /// The phone watching the real board. It is looked for from launch and
    /// connected when the player asks, to follow the game played there.
    public let phone = PhoneLink()

    /// The Mac follows the game on the real board: every position the phone sends
    /// goes to the bridge, which turns it into moves. True from the moment the
    /// player connects until they disconnect or start something else.
    public private(set) var isFollowing = false
    /// The phone said the game was over; the record is on screen, and the next
    /// position the phone sends starts the next game.
    private var followedGameEnded = false

    /// The player asked to connect while a game was under way: the sidebar asks
    /// whether to save it first.
    public var isConfirmingFollow = false
    /// The sheet listing the phones in sight is open, for the player to pick one.
    public var isChoosingPhone = false
    /// The game is being saved before following starts; the save panel's answer
    /// starts it.
    private var followsAfterExport = false

    /// Score lead per move number, filled in as analyses come back.
    public private(set) var scoreByMove: [Int: Double] = [:]

    /// How far KataGo has got through a record under review, nil when it is done
    /// or when no record is open.
    public private(set) var analysisProgress: (done: Int, total: Int)?

    /// The record's file name, for the window title.
    public private(set) var recordName: String?

    /// The tree of variations as the bridge last sent it, and its layout.
    public private(set) var tree: [TreeNode] = []
    public private(set) var treeLayout = TreeLayout(nodes: [])

    /// The record on screen as it was read from disk, and the `load_sgf` that
    /// opened it. Its analysis is written back to that file, and only an answer to
    /// that very command may write it.
    private var openedRecord: (record: SGFImport.Record, command: Int)?
    var openedRecordCommand: Int? { openedRecord?.command }

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
        phone.onGameEnd = { [weak self] end in self?.phoneGameDidEnd(end) }
    }

    // -- lifecycle -----------------------------------------------------------

    /// Starts the bridge once. Later calls do nothing, so a view coming back up
    /// never launches a second KataGo.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        phone.startDiscovery()
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
        case .ready(_, _, let strategies, let settings):
            phase = .running
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

        case .tree(let nodes):
            tree = nodes
            treeLayout = TreeLayout(nodes: nodes)

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

        case .recordAnalysed(let id, let contents):
            guard let opened = openedRecord, opened.command == id else { break }
            openedRecord = nil
            do {
                try SGFExport.rewrite(contents, over: opened.record)
            } catch {
                lastErrorMessage = error.localizedDescription
            }

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
    ///
    /// `not_following` is a position the phone sent just as following stopped.
    private static let silentFailures: Set<String> = ["illegal_move", "no_variation", "not_following"]

    private func apply(_ newState: GameState) {
        // Moves beyond the current one no longer exist, typically after an undo —
        // but in analysis the game has a future as well as a past, and stepping back
        // through it, or into a branch, must not rub out the chart of the game.
        let lastOfGame = newState.isAnalysing ? newState.moveCount ?? newState.moveNumber : newState.moveNumber
        scoreByMove = scoreByMove.filter { $0.key <= lastOfGame }
        for (index, score) in newState.scoreHistory.enumerated() {
            if let score { scoreByMove[index] = score }
        }
        state = newState
        if newState.status != .playing || newState.isAnalysing { thinking.ended() }
    }

    // -- following a game on a real board ------------------------------------

    /// A game is under way that following would replace: worth asking first.
    public var hasGameInProgress: Bool {
        guard let state, !isFollowing else { return false }
        return state.status == .scoring || (state.status == .playing && state.moveNumber > 0)
    }

    /// The player clicked "Connecter". A game under way is not dropped without
    /// asking: the sidebar first offers to save it, or to give it up. Then the
    /// phones in sight are listed, for the player to pick one.
    public func connectPhone() {
        if isFollowing {
            phone.connect()  // the link dropped or failed: the game followed goes on
        } else if hasGameInProgress {
            isConfirmingFollow = true
        } else {
            choosePhone()
        }
    }

    /// Opens the list of phones running Kifu.
    public func choosePhone() {
        isConfirmingFollow = false
        phone.startDiscovery()
        isChoosingPhone = true
    }

    /// The player picked a phone, by its Bonjour service: follow the game it records.
    public func follow(phone service: String) {
        isChoosingPhone = false
        startFollowing(phone: service)
    }

    /// Saves the game under way, then follows the real board whatever the panel's answer.
    public func saveThenFollow() {
        followsAfterExport = true
        exportRecord()
    }

    /// Starts following: an empty game with no AI, and the chosen phone's link opened.
    /// The phone sends its position on connecting, which the bridge takes as the
    /// start — a game recorded halfway is joined where it stands.
    func startFollowing(phone service: String) {
        guard phase == .running else { return }
        isConfirmingFollow = false
        isFollowing = true
        beginFollowedGame(size: 19)
        phone.connect(to: service)
    }

    /// Stops following. The game followed so far opens as a record, its analyses
    /// kept — unless something else is about to take the window.
    public func stopFollowing(openingRecord: Bool = true) {
        guard isFollowing else { return }
        isFollowing = false
        phone.disconnect()
        let ended = followedGameEnded
        followedGameEnded = false
        guard openingRecord, !ended, let state, state.isFollowing else { return }
        // Nothing was seen: there is no record to open, only a game to start.
        if state.moveNumber == 0, state.stones.isEmpty {
            newGame()
        } else {
            bridge.send(.followEnd(id: nextID(), result: nil))
        }
    }

    private func beginFollowedGame(size: Int) {
        followedGameEnded = false
        scoreByMove.removeAll()
        state = nil
        lastErrorMessage = nil
        recordName = nil
        openedRecord = nil
        analysisProgress = nil
        thinking.ended()
        bridge.send(
            .followStart(id: nextID(), size: size, komi: settings.komi, rules: settings.rules, analysis: followsWithAnalysis)
        )
    }

    /// Whether KataGo analyses the game followed: the score and its curve, the best
    /// move, and the best move near the last one with what it costs. Off, KataGo
    /// computes nothing.
    public var followsWithAnalysis: Bool {
        get { settings.followAnalysis ?? true }
        set {
            settings.followAnalysis = newValue
            store.save(settings)
            if state?.isFollowing == true { bridge.send(.followAnalysis(id: nextID(), on: newValue)) }
        }
    }

    /// The real board changed. While following, the position goes to the bridge;
    /// after a game has ended, the next one starts with it.
    private func phoneBoardDidChange(_ board: PhoneBoard) {
        guard phase == .running, isFollowing else { return }
        if followedGameEnded || (state?.isFollowing == true && state?.size != board.size && state?.moveNumber == 0) {
            beginFollowedGame(size: board.size)
        }
        bridge.send(.followBoard(id: nextID(), rows: board.rows, history: board.history))
    }

    /// The phone says the game is over: it opens as a record under review, and the
    /// link stays open for the next game.
    private func phoneGameDidEnd(_ end: PhoneGameEnd) {
        guard phase == .running, isFollowing, !followedGameEnded else { return }
        followedGameEnded = true
        bridge.send(.followEnd(id: nextID(), result: end.result))
    }

    // -- commands ------------------------------------------------------------

    private func nextID() -> Int {
        defer { nextCommandID += 1 }
        return nextCommandID
    }

    public func newGame() {
        stopFollowing(openingRecord: false)
        store.save(settings)
        scoreByMove.removeAll()
        state = nil
        lastErrorMessage = nil
        recordName = nil
        openedRecord = nil
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
        guard canPlace else { return }
        bridge.send(.play(id: nextID(), row: row, col: col))
    }

    public func passTurn() {
        guard canAct || isAnalysing else { return }
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
        guard canUndo else { return }
        bridge.send(.undo(id: nextID()))
    }

    /// Against the AI, the last moves played; in analysis, the stone just placed by
    /// hand or the last move of KataGo's line being walked.
    public var canUndo: Bool {
        guard let state else { return false }
        if state.isAnalysing { return (state.variationDepth ?? 0) > 0 || isOnLeafOfAnalysis }
        return state.status == .playing
    }

    public func resign() {
        guard state != nil, state?.status == .playing else { return }
        bridge.send(.resign(id: nextID()))
    }

    /// Dismisses the last failure, once the player has seen it.
    public func clearError() {
        lastErrorMessage = nil
    }

    // -- analysis ------------------------------------------------------------

    /// True once a record is open and being read, with no game behind it.
    public var isReviewing: Bool { state?.isReviewing ?? false }

    /// The board shows the tree: stones placed by hand, both colours in turn.
    public var isAnalysing: Bool { state?.isAnalysing ?? false }

    /// The toggle at the top of the window has something to switch to.
    public var hasLiveGame: Bool { state?.hasLiveGame ?? false }

    /// The toggle can be moved. While counting, asking for the analysis settles the
    /// count as it stands, and the game is over.
    public var canSwitchView: Bool { phase == .running && hasLiveGame }

    /// Switches between the game itself and its analysis.
    public func setView(_ view: GameView) {
        guard canSwitchView, state?.isAnalysing != (view == .analysis) else { return }
        bridge.send(.setView(id: nextID(), view: view))
    }

    /// A click in the tree.
    public func gotoNode(_ id: Int) {
        guard phase == .running, state?.status != .scoring else { return }
        bridge.send(.gotoNode(id: nextID(), nodeID: id))
    }

    /// The arrow keys, in the tree.
    public func navigate(_ destination: TreeDestination) {
        guard isAnalysing else { return }
        bridge.send(.navigate(id: nextID(), to: destination))
    }

    /// Drops a branch placed in analysis, from this node down.
    public func deleteBranch(_ id: Int) {
        guard isAnalysing, isDeletable(id) else { return }
        bridge.send(.deleteBranch(id: nextID(), nodeID: id))
    }

    /// Only the player's own stones can be deleted, never the game nor the record.
    public func isDeletable(_ id: Int) -> Bool {
        tree.first { $0.id == id }?.origin == .analysis
    }

    /// The node on screen, as the tree knows it.
    public var currentNode: TreeNode? {
        guard let id = state?.nodeId else { return nil }
        return tree.first { $0.id == id }
    }

    /// The node on screen was placed by hand and nothing follows it.
    public var isOnLeafOfAnalysis: Bool {
        guard let node = currentNode, node.origin == .analysis else { return false }
        return !tree.contains { $0.parent == node.id }
    }

    /// The node on screen is in a branch, off the line of the game.
    public var isInBranch: Bool {
        guard let node = currentNode else { return false }
        return node.origin != .game
    }

    /// Siblings of the node on screen, to step across with ↑ and ↓.
    private var siblings: [TreeNode] {
        guard let node = currentNode, let parent = node.parent else { return [] }
        return tree.filter { $0.parent == parent }
    }

    public var hasPreviousSibling: Bool { siblings.first.map { $0.id != state?.nodeId } ?? false }
    /// ↓ has somewhere to go: a branch starting after the move on screen, which it
    /// enters first, or the next variation beside it.
    public var hasNextSibling: Bool {
        if let id = state?.nodeId, tree.filter({ $0.parent == id }).count > 1 { return true }
        return siblings.last.map { $0.id != state?.nodeId } ?? false
    }

    /// Opens a record, replacing whatever the window was showing.
    ///
    /// The file is read here and sent as text: the bridge opens nothing, which keeps
    /// the sandbox out of the child process and the encoding guess in AppKit's hands.
    public func openRecord(at url: URL) {
        do {
            load(try SGFImport.read(url))
        } catch {
            recordName = nil
            openedRecord = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Hands a record to the bridge, or holds it until the bridge is ready for one.
    private func load(_ record: SGFImport.Record) {
        stopFollowing(openingRecord: false)
        scoreByMove.removeAll()
        analysisProgress = nil
        lastErrorMessage = nil
        recordName = record.name
        openedRecord = nil
        thinking.ended()
        guard phase == .running else {
            recordWaiting = record
            return
        }
        let command = nextID()
        if record.url != nil { openedRecord = (record, command) }
        bridge.send(.loadSGF(id: command, name: record.name, contents: record.contents))
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
        if !isReviewing, !isFollowing, let state {
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

    /// The player saved the game themselves. Over the record's own file, that save
    /// is the one to keep — it may carry the variation being walked — so the
    /// analysis is no longer written there behind their back.
    public func recordSaved(to url: URL) {
        guard let opened = openedRecord?.record.url else { return }
        if opened.standardizedFileURL.path == url.standardizedFileURL.path {
            openedRecord = nil
        }
    }

    /// The save panel is done with the document, written or not.
    public func exportHandled() {
        pendingExport = nil
        if followsAfterExport {
            followsAfterExport = false
            choosePhone()
        }
    }

    /// Moves to a position in the line of the game. The bridge clamps anything out
    /// of range.
    public func goto(moveNumber: Int) {
        guard isAnalysing else { return }
        bridge.send(.goto(id: nextID(), moveNumber: moveNumber))
    }

    /// One move back or forward in the tree: back to the parent, forward along the
    /// branch last walked. Inside KataGo's line, the moves walked so far stay as a
    /// branch and the arrow steps along it; only ⌥← and ⇧⌥← take them back.
    public func step(_ delta: Int) {
        navigate(delta < 0 ? .back : .forward)
    }

    /// One move of a continuation, added or taken back: KataGo's own, or the local one.
    public func stepVariation(_ delta: Int, kind: VariationKind = .best) {
        guard isAnalysing else { return }
        bridge.send(.variation(id: nextID(), step: delta > 0 ? 1 : -1, kind: kind))
    }

    /// Whether the board shows the local reading — zone, blue disc, loader — next to
    /// the best move. Always in a review, where the bridge reads every position it
    /// lands on; while following, only with KataGo's analysis on.
    public var showsLocalReading: Bool {
        if state?.isAnalysing == true { return true }
        return state?.isFollowing == true && state?.analysis == true
    }

    /// Reads the fight inside a zone drawn on the board, until it is cleared.
    public func drawLocalZone(_ zone: LocalZone) {
        guard isAnalysing else { return }
        bridge.send(.setLocalZone(id: nextID(), zone: zone))
    }

    /// Hands the zone back to the bridge, which infers it around the last move.
    public func clearDrawnZone() {
        guard hasDrawnZone else { return }
        bridge.send(.setLocalZone(id: nextID(), zone: nil))
    }

    public var hasDrawnZone: Bool {
        isAnalysing && state?.localZoneDrawn == true
    }

    /// Whether the local sequence can be started or walked further.
    public var canWalkLocal: Bool {
        guard let state, state.isAnalysing else { return false }
        return state.localZone != nil
    }

    /// Whether a local sequence is under way, so it can be taken back.
    public var isWalkingLocal: Bool {
        state?.variationKind == .local && (state?.variationDepth ?? 0) > 0
    }

    public var canStepBackward: Bool {
        guard let state, state.isAnalysing else { return false }
        return state.moveNumber > 0 || (state.variationDepth ?? 0) > 0
    }

    /// Something follows the position on screen in the tree.
    public var canStepForward: Bool {
        guard let state, state.isAnalysing, let id = state.nodeId else { return false }
        return tree.contains { $0.parent == id }
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
        // In a branch the chart's figure for that move number is the game's, not the
        // position on screen: the position's own score comes first there.
        let lead =
            (isInBranch ? state.scoreLead : nil)
            ?? scoreByMove[state.moveNumber]
            ?? state.scoreLead
            ?? Self.latestLead(in: scoreByMove, upTo: state.moveNumber)
        return lead.map { $0 * sign }
    }

    /// Whether the score estimate is on: the bridge's word, not ours.
    public var isEstimating: Bool { state?.estimating == true }

    /// The estimate needs KataGo reading the position: in a game, in a review, and
    /// in a game followed with the analysis on. Not once the game is counted.
    public var canEstimate: Bool {
        guard phase == .running, let state else { return false }
        if state.isAnalysing { return true }
        switch state.status {
        case .playing, .review: return true
        case .following: return state.analysis == true
        case .scoring, .finished: return false
        }
    }

    /// Shows the estimate, or hides it. It stays on move after move until hidden.
    public func toggleEstimate() {
        guard canEstimate || isEstimating else { return }
        bridge.send(.estimate(id: nextID(), on: !isEstimating))
    }

    /// Whether the weak points are on: the bridge's word, not ours.
    public var isShowingWeaknesses: Bool { state?.weaknessing == true }

    /// The weak points are a question asked in analysis, never during a game.
    public var canShowWeaknesses: Bool { phase == .running && isAnalysing }

    /// Shows the weak points, or hides them. They stay on from one position to the next.
    public func toggleWeaknesses() {
        guard canShowWeaknesses else { return }
        bridge.send(.weaknesses(id: nextID(), on: !isShowingWeaknesses))
    }

    /// True when the player may act: a game is running and it is their turn.
    ///
    /// `isHumanTurn` is false in analysis, where `canPlace` takes over.
    public var canAct: Bool {
        phase == .running && !isAnalysing && (state?.isHumanTurn ?? false)
    }

    /// A click on the board places a stone: the player's move against the AI, any
    /// colour in analysis, and while following a question that opens the analysis.
    public var canPlace: Bool {
        guard phase == .running, let state else { return false }
        return canAct || state.isAnalysing || state.status == .following
    }
}
