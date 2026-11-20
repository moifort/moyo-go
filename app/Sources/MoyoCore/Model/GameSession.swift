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
        case failed(EngineFailure)
    }

    /// Why there is no game on screen: an engine that never came up, or one that
    /// stopped later on. The detail is the diagnostic, shown selectable.
    public struct EngineFailure: Equatable, Sendable {
        public enum Moment: Equatable, Sendable { case startup, stopped }
        public let moment: Moment
        public let detail: String

        public var title: String {
            moment == .startup ? "Le moteur n'a pas démarré" : "Le moteur s'est arrêté"
        }
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
    /// The last failure worth telling the player, until they dismiss it.
    public private(set) var lastError: SessionError?
    public var lastErrorMessage: String? { lastError?.message }
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

    /// The sheet listing the phones in sight is open, for the player to pick one.
    public var isChoosingPhone = false

    /// Score lead per move number, filled in as analyses come back.
    public private(set) var scoreByMove: [Int: Double] = [:]

    /// How far KataGo has got through a record under review, nil when it is done
    /// or when no record is open.
    public private(set) var analysisProgress: (done: Int, total: Int)?
    /// How many positions KataGo has read, kept after it is done: the library
    /// writes the record again each time it moves.
    private var analysisDone: Int?

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
    private var recordWaitingEntry: (id: UUID?, kind: LibraryEntry.Kind, hash: String?) = (nil, .record, nil)

    var hasRecordWaiting: Bool { recordWaiting != nil }

    /// A game the bridge has turned into text, waiting for the save panel.
    public private(set) var pendingExport: SGFExport.Document?

    // -- the library ------------------------------------------------------------

    /// Every game played, reviewed or followed, kept as it goes.
    public let library: GameLibrary

    /// The window shows the library rather than the game. Going back to it leaves
    /// the game where it stands in the engine.
    public var isShowingLibrary = true

    /// The library's game the session is holding, drawn at each start: a new game,
    /// a record opened, a game followed — and each next game the phone chains.
    struct EntryContext: Equatable {
        let id: UUID
        let kind: LibraryEntry.Kind
        let createdAt: Date
        let sourceHash: String?
    }

    private(set) var currentEntry: EntryContext?
    public var currentEntryID: UUID? { currentEntry?.id }

    /// What an autosave asked for, kept until the bridge's answer: by then the
    /// session may already hold another game.
    private struct AutosaveRequest {
        let entry: EntryContext
        let status: LibraryEntry.Status
        let komi: Double
        let humanColor: PlayerColor?
        let aiStrategy: String?
        let aiSettingValue: Double?
    }

    private var autosaves: [Int: AutosaveRequest] = [:]
    private var autosaveTask: Task<Void, Never>?
    /// The shape of the work when it was last sent to the library.
    private var autosavedWork: String?
    /// The record last written for each game: an answer that says the same thing
    /// again changes nothing, and does not move the game up the grid.
    private var written: [UUID: String] = [:]
    /// How long changes are gathered before the game is written.
    var autosaveDelay: Duration = .seconds(2)
    /// Waiting for the last autosaves before the app quits.
    private var quitting: [() -> Void] = []

    private var bridge: BridgeProcess
    private let makeBridge: () -> BridgeProcess
    private let location: () -> BridgeLocation?
    private let store: SettingsStore
    private var nextCommandID = 1
    private var hasStarted = false
    private var eventTask: Task<Void, Never>?

    public init(
        bridge: BridgeProcess = BridgeProcess(),
        store: SettingsStore = SettingsStore(),
        makeBridge: @escaping () -> BridgeProcess = { BridgeProcess() },
        location: @escaping () -> BridgeLocation? = { BridgeLocation.resolve() },
        library: GameLibrary = GameLibrary(directory: nil)
    ) {
        self.library = library
        self.bridge = bridge
        self.makeBridge = makeBridge
        self.location = location
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
        guard let location = location() else {
            phase = .failed(
                EngineFailure(
                    moment: .startup,
                    detail: "Emplacement du projet inconnu. Définissez MOYO_DEV_ROOT ou reconstruisez l'application."
                )
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
                // A bridge replaced by a restart ends here too: that is no failure.
                guard !Task.isCancelled else { return }
                self?.bridgeDidStop()
            }
        } catch {
            phase = .failed(EngineFailure(moment: .startup, detail: error.localizedDescription))
        }
    }

    public func stop() {
        eventTask?.cancel()
        bridge.stop()
    }

    /// The bridge's output ended. Internal so the tests can stop it.
    func bridgeDidStop() {
        if case .failed = phase { return }
        phase = .failed(
            phase == .running
                ? EngineFailure(moment: .stopped, detail: "La partie en cours est perdue. Le journal du moteur dit pourquoi.")
                : EngineFailure(moment: .startup, detail: "Le moteur s'est arrêté avant d'être prêt.")
        )
    }

    /// Where the bridge writes its diagnostics, once it has been launched.
    public var logURL: URL? { bridge.logURL }

    /// Starts a new bridge in place of the one that stopped.
    public func restartEngine() {
        eventTask?.cancel()
        eventTask = nil
        bridge.stop()
        bridge = makeBridge()
        hasStarted = false
        state = nil
        tree = []
        treeLayout = TreeLayout(nodes: [])
        lastError = nil
        thinking.ended()
        phase = .starting
        start()
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
                load(record, entry: recordWaitingEntry)
            } else {
                startNewGame()
            }

        case .state(_, let newState):
            apply(newState)
            workDidChange()

        case .tree(let nodes):
            tree = nodes
            treeLayout = TreeLayout(nodes: nodes)
            workDidChange()

        case .thinking(let value):
            value ? thinking.began() : thinking.ended()

        case .score(let moveNumber, let scoreLead):
            scoreByMove[moveNumber] = scoreLead

        case .analysisProgress(let done, let total):
            analysisProgress = done >= total ? nil : (done, total)
            analysisDone = done
            workDidChange()

        case .sgf(let id, let answer):
            if answer.reason == .autosave {
                if let id, let request = autosaves.removeValue(forKey: id) {
                    keep(answer, for: request)
                }
                if autosaves.isEmpty { finishQuitting() }
                break
            }
            pendingExport = SGFExport.Document(
                name: SGFExport.suggestedName(recordName: isReviewing ? recordName : nil, date: .now),
                contents: answer.contents
            )

        case .recordAnalysed(let id, let contents):
            guard let opened = openedRecord, opened.command == id else { break }
            openedRecord = nil
            do {
                try SGFExport.rewrite(contents, over: opened.record)
            } catch {
                lastError = SessionError(kind: .saving, message: error.localizedDescription)
            }

        case .failure(_, let code, let message):
            // Some refusals are answers, not faults: those stay silent. The others
            // are said in the app's words, chosen from the code.
            if let error = SessionError.fromBridge(code: code, message: message) {
                lastError = error
            }

        case .engineFailed(let message):
            phase = .failed(EngineFailure(moment: .startup, detail: message))

        case .unknown:
            break
        }
    }

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

    /// The player clicked "Connecter". Work under way is not dropped without
    /// asking: the window first offers to save it, or to replace it. Then the
    /// phones in sight are listed, for the player to pick one.
    public func connectPhone() {
        if isFollowing {
            phone.connect()  // the link dropped or failed: the game followed goes on
        } else {
            replaceOrAsk(.follow)
        }
    }

    /// Opens the list of phones running Kifu.
    public func choosePhone() {
        phone.startDiscovery()
        isChoosingPhone = true
    }

    /// The player picked a phone, by its Bonjour service: follow the game it records.
    public func follow(phone service: String) {
        isChoosingPhone = false
        startFollowing(phone: service)
    }

    // -- replacing the work on screen -----------------------------------------

    /// What the player asked for that would take the window's place.
    public enum Replacement: Equatable, Sendable {
        case newGame
        case record(SGFImport.Record)
        case follow
    }

    /// What changes when the player adds to the work: moves played, nodes added.
    private var workSignature: String? {
        guard let state else { return nil }
        return "\(state.status)|\(state.moveCount ?? state.moveNumber)|\(tree.count)"
    }

    /// Nothing is ever lost by replacing the work on screen: the library keeps it.
    /// Its last state goes to the bridge first, and the bridge answers in order, so
    /// the record is written before anything replaces it.
    private func replaceOrAsk(_ replacement: Replacement) {
        perform(replacement)
    }

    private func perform(_ replacement: Replacement) {
        switch replacement {
        case .newGame: newGame()
        case .record(let record): open(record)
        case .follow: choosePhone()
        }
    }

    /// The sheet's "Commencer": a new game, the one on screen kept in the library.
    public func requestNewGame() {
        replaceOrAsk(.newGame)
    }

    /// A record read from disk, opened in place of the work on screen.
    public func requestOpening(_ record: SGFImport.Record) {
        replaceOrAsk(.record(record))
    }

    /// Starts following: an empty game with no AI, and the chosen phone's link opened.
    /// The phone sends its position on connecting, which the bridge takes as the
    /// start — a game recorded halfway is joined where it stands.
    func startFollowing(phone service: String) {
        guard phase == .running else { return }
        isFollowing = true
        isShowingLibrary = false
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
        flushAutosave()
        beginEntry(.kifu)
        followedGameEnded = false
        scoreByMove.removeAll()
        state = nil
        lastError = nil
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

    /// A new game against KataGo, on screen.
    public func newGame() {
        startNewGame()
        isShowingLibrary = false
    }

    /// A new game against KataGo, wherever the window is: the one the engine opens
    /// on waits behind the library until the player asks for it.
    private func startNewGame() {
        flushAutosave()
        stopFollowing(openingRecord: false)
        beginEntry(.ai)
        store.save(settings)
        scoreByMove.removeAll()
        state = nil
        lastError = nil
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

    /// The player asked to give up, from the sidebar or the menu: the window asks
    /// whether they mean it before anything is sent.
    public var isConfirmingResignation = false

    public func requestResignation() {
        guard state?.status == .playing else { return }
        isConfirmingResignation = true
    }

    public func resign() {
        isConfirmingResignation = false
        guard state != nil, state?.status == .playing else { return }
        bridge.send(.resign(id: nextID()))
    }

    /// Dismisses the last failure, once the player has seen it.
    public func clearError() {
        lastError = nil
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
            requestOpening(try SGFImport.read(url))
        } catch {
            recordName = nil
            openedRecord = nil
            lastError = SessionError(kind: .opening, message: error.localizedDescription)
        }
    }

    /// A record read from disk. The same text opened before is the same game: it
    /// reopens from the library's record, with its branches and its analysis.
    private func open(_ record: SGFImport.Record) {
        let hash = GameLibrary.fingerprint(record.contents)
        if let entry = library.entry(sourceHash: hash), let kept = library.contents(of: entry.id) {
            written[entry.id] = kept
            load(SGFImport.Record(name: record.name, contents: kept), entry: (entry.id, entry.kind, hash))
        } else {
            load(record, entry: (nil, .record, hash))
        }
    }

    /// Hands a record to the bridge, or holds it until the bridge is ready for one.
    /// `entry` is the library's game it belongs to: an existing one, or a new one
    /// of that kind.
    private func load(_ record: SGFImport.Record, entry: (id: UUID?, kind: LibraryEntry.Kind, hash: String?)) {
        flushAutosave()
        isShowingLibrary = false
        stopFollowing(openingRecord: false)
        scoreByMove.removeAll()
        analysisProgress = nil
        lastError = nil
        recordName = record.name
        openedRecord = nil
        thinking.ended()
        guard phase == .running else {
            recordWaiting = record
            recordWaitingEntry = entry
            return
        }
        beginEntry(entry.kind, reusing: entry.id, sourceHash: entry.hash)
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
        let players = signingNames
        bridge.send(.exportSGF(id: nextID(), blackName: players.black, whiteName: players.white))
    }

    /// Who signs a game against the AI. A record keeps its own names.
    private var signingNames: (black: String?, white: String?) {
        guard !isReviewing, !isFollowing, state?.isFollowing != true, let state else { return (nil, nil) }
        let mode = currentMode
        return SGFExport.players(
            humanColor: state.humanColor,
            human: NSFullUserName(),
            ai: SGFExport.aiName(mode: mode, value: settingValue(for: mode))
        )
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

    /// The komi of the game on screen: a record or a followed game need not have
    /// the one in the settings.
    public var komi: Double { state?.komi ?? settings.komi }

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

    // -- the library ------------------------------------------------------------

    /// A new game for the library, or one it already holds picked up again.
    private func beginEntry(_ kind: LibraryEntry.Kind, reusing id: UUID? = nil, sourceHash: String? = nil) {
        autosaveTask?.cancel()
        autosaveTask = nil
        autosavedWork = nil
        analysisDone = nil
        let existing = id.flatMap(library.entry)
        currentEntry = EntryContext(
            id: existing?.id ?? id ?? UUID(),
            kind: existing?.kind ?? kind,
            createdAt: existing?.createdAt ?? .now,
            sourceHash: existing?.sourceHash ?? sourceHash
        )
    }

    /// What the library writes again when it changes: the work itself, and how far
    /// KataGo has read it.
    private var autosaveSignature: String? {
        guard let work = workSignature else { return nil }
        return "\(work)|\(analysisDone ?? -1)"
    }

    /// A game against KataGo or a game followed is worth keeping from its first
    /// move; a record, from the moment it is open.
    private var isWorthKeeping: Bool {
        guard let state, let entry = currentEntry else { return false }
        return entry.kind == .record || (state.moveCount ?? state.moveNumber) > 0
    }

    /// The work changed: it is written once the changes settle, at once when the
    /// game has just ended.
    private func workDidChange() {
        guard currentEntry != nil, let signature = autosaveSignature, signature != autosavedWork,
              isWorthKeeping
        else { return }
        if state?.status == .finished, autosavedWork?.hasPrefix("\(GameStatus.finished)|") != true {
            flushAutosave()
            return
        }
        guard autosaveTask == nil else { return }
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.autosaveTask = nil
            self?.flushAutosave()
        }
    }

    /// Asks the bridge for the game as it stands, for the library. Returns whether
    /// an answer is on its way.
    @discardableResult
    func flushAutosave() -> Bool {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard phase == .running, let entry = currentEntry, let state, let signature = autosaveSignature,
              signature != autosavedWork, isWorthKeeping
        else { return false }
        autosavedWork = signature
        let status: LibraryEntry.Status
        switch entry.kind {
        case .ai: status = state.status == .finished ? .finished : .inProgress
        case .kifu: status = state.isFollowing ? .inProgress : .finished
        case .record: status = .finished
        }
        let mode = currentMode
        let players = signingNames(for: entry)
        let command = nextID()
        autosaves[command] = AutosaveRequest(
            entry: entry,
            status: status,
            komi: state.komi ?? settings.komi,
            humanColor: entry.kind == .ai ? state.humanColor : nil,
            aiStrategy: entry.kind == .ai ? (state.aiStrategy ?? settings.aiStrategy) : nil,
            aiSettingValue: entry.kind == .ai ? settingValue(for: mode) : nil
        )
        bridge.send(.exportSGF(id: command, blackName: players.black, whiteName: players.white, autosave: true))
        return true
    }

    private func signingNames(for entry: EntryContext) -> (black: String?, white: String?) {
        entry.kind == .ai && state?.isReviewing != true ? signingNames : (nil, nil)
    }

    /// Writes what the bridge answered to an autosave.
    private func keep(_ answer: SGFAnswer, for request: AutosaveRequest) {
        let id = request.entry.id
        let previous = library.entry(id)
        if previous != nil, written[id] == answer.contents { return }
        let info = answer.gameInfo
        let size = answer.finalBoard?.size ?? previous?.size ?? state?.size ?? settings.size
        let entry = LibraryEntry(
            id: id,
            kind: request.entry.kind,
            createdAt: request.entry.createdAt,
            updatedAt: .now,
            size: size,
            komi: request.komi,
            blackName: info?.blackName ?? previous?.blackName,
            whiteName: info?.whiteName ?? previous?.whiteName,
            humanColor: request.humanColor ?? previous?.humanColor,
            aiStrategy: request.aiStrategy ?? previous?.aiStrategy,
            aiSettingValue: request.aiSettingValue ?? previous?.aiSettingValue,
            result: info?.result,
            moveCount: answer.moveCount ?? previous?.moveCount ?? 0,
            status: request.status,
            analysis: answer.analysed.map { LibraryEntry.Analysis(done: $0.done, total: $0.total) }
                ?? previous?.analysis ?? .none,
            finalBoard: answer.finalBoard ?? previous?.finalBoard ?? .empty(size: size),
            sourceHash: request.entry.sourceHash,
            title: request.entry.kind == .ai ? nil : (info?.gameName ?? info?.event)
        )
        do {
            try library.save(entry, contents: answer.contents)
            written[id] = answer.contents
        } catch {
            lastError = SessionError(kind: .saving, message: error.localizedDescription)
        }
    }

    /// The app is about to quit: the game on screen is written first. `done` is
    /// called once it is, or after two seconds whatever happens.
    public func prepareToQuit(_ done: @escaping () -> Void) {
        flushAutosave()
        guard !autosaves.isEmpty else {
            done()
            return
        }
        quitting.append(done)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.finishQuitting()
        }
    }

    private func finishQuitting() {
        let waiting = quitting
        quitting = []
        waiting.forEach { $0() }
    }

    /// Back to the grid. The game stays where it is in the engine; it is written
    /// now, so its card is up to date.
    public func showLibrary() {
        flushAutosave()
        isShowingLibrary = true
    }

    /// The game the engine holds, when it is a game against KataGo still under way.
    public var liveEntry: LibraryEntry? {
        guard let id = currentEntryID, let state, state.status == .playing || state.status == .scoring,
              currentEntry?.kind == .ai
        else { return nil }
        return library.entry(id)
    }

    /// Whether a card is the game the engine holds right now.
    public func isOnScreen(_ entry: LibraryEntry) -> Bool {
        entry.id == currentEntryID && state != nil
    }

    /// A card was opened: the game on screen if it is that one, a game against
    /// KataGo picked up where it was left, anything else read from its record.
    public func open(_ entry: LibraryEntry) {
        guard phase == .running else { return }
        if isOnScreen(entry) {
            isShowingLibrary = false
            return
        }
        guard let contents = library.contents(of: entry.id) else {
            lastError = SessionError(kind: .opening, message: "Le fichier de cette partie est introuvable.")
            return
        }
        written[entry.id] = contents
        guard entry.canResume, let color = entry.humanColor else {
            load(
                SGFImport.Record(name: entry.displayTitle, contents: contents),
                entry: (entry.id, entry.kind, entry.sourceHash)
            )
            return
        }
        flushAutosave()
        stopFollowing(openingRecord: false)
        beginEntry(.ai, reusing: entry.id)
        isShowingLibrary = false
        scoreByMove.removeAll()
        state = nil
        lastError = nil
        recordName = nil
        openedRecord = nil
        analysisProgress = nil
        let strategy = entry.aiStrategy ?? settings.aiStrategy
        var payload: [String: Double] = [:]
        if let setting = AIMode.mode(for: strategy).setting, let value = entry.aiSettingValue {
            payload[setting.key] = value
        }
        bridge.send(
            .continueGame(id: nextID(), contents: contents, humanColor: color, aiStrategy: strategy, aiSettings: payload)
        )
    }

    /// The game the engine holds while it is played or followed cannot go: the
    /// library would write it straight back.
    public func canDelete(_ entry: LibraryEntry) -> Bool {
        !(entry.id == currentEntryID && state?.hasLiveGame == true)
    }

    /// Removes a game from the library for good. A game on screen but over stays on
    /// screen, no longer kept.
    public func delete(_ entry: LibraryEntry) {
        guard canDelete(entry) else { return }
        if entry.id == currentEntryID {
            autosaveTask?.cancel()
            autosaveTask = nil
            currentEntry = nil
        }
        written[entry.id] = nil
        do {
            try library.delete(entry.id)
        } catch {
            lastError = SessionError(kind: .saving, message: error.localizedDescription)
        }
    }

    /// "Exporter en SGF…" on a card: the record kept, through the save panel.
    public func export(_ entry: LibraryEntry) {
        guard let contents = library.contents(of: entry.id) else { return }
        let name = entry.kind == .ai ? nil : entry.displayTitle
        pendingExport = SGFExport.Document(
            name: SGFExport.suggestedName(recordName: name, date: entry.createdAt),
            contents: contents
        )
    }
}
