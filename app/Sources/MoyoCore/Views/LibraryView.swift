import SwiftUI

/// What the window opens on: every game kept, its last position in a thumbnail,
/// the most recent first.
///
/// A band at the top picks up the game under way against KataGo, or the last one;
/// below it, wide cards three to a row, each with its result in large, where it
/// comes from, and what can be done with it.
public struct LibraryView: View {
    @Bindable public var session: GameSession
    @State private var filter: LibraryFilter = .all
    @State private var search = ""
    @State private var order: LibraryOrder = .newest
    @State private var deleting: LibraryEntry?

    public init(session: GameSession) {
        self.session = session
    }

    private var entries: [LibraryEntry] { session.library.entries }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(216)
        } detail: {
            ZStack {
                Theme.windowBackground.ignoresSafeArea()
                if entries.isEmpty {
                    emptyLibrary
                } else {
                    grid
                }
            }
        }
        .navigationTitle("Moyo")
        .navigationSubtitle(LibraryText.count(entries.count))
        .searchable(text: $search, placement: .toolbar, prompt: "Rechercher")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Ordre", selection: $order) {
                    ForEach(LibraryOrder.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Ordre des parties")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Nouvelle partie") {
                    NotificationCenter.default.post(name: .moyoNewGameRequested, object: nil)
                }
                .buttonStyle(.glassProminent)
                .disabled(!isReady)
                .help("Commencer une partie contre KataGo (⌘N)")
            }
        }
        .sheet(isPresented: $session.isChoosingPhone) {
            PhonePicker(phones: session.phone.phones) { phone in
                session.follow(phone: phone.id)
            } cancel: {
                session.isChoosingPhone = false
            }
        }
        .confirmationDialog(
            "Supprimer cette partie ?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { entry in
            Button("Supprimer", role: .destructive) { session.delete(entry) }
            Button("Annuler", role: .cancel) {}
        } message: { entry in
            Text("« \(entry.displayTitle) » sera supprimée de la bibliothèque. Cette action est irréversible.")
        }
    }

    private var isReady: Bool { session.phase == .running }

    // -- sidebar ------------------------------------------------------------------

    private var sidebar: some View {
        List(selection: Binding(get: { filter }, set: { filter = $0 ?? .all })) {
            Section("Bibliothèque") {
                ForEach([LibraryFilter.all, .ai, .record, .kifu]) { row($0) }
            }
            Section("À faire") {
                ForEach([LibraryFilter.toResume, .analysisIncomplete]) { row($0) }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ filter: LibraryFilter) -> some View {
        HStack(spacing: 9) {
            if let dot = filter.dot {
                Circle().fill(dot).frame(width: 9, height: 9)
            }
            Text(filter.label)
            Spacer()
            Text("\(entries.filter(filter.includes).count)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
        .tag(filter)
    }

    // -- grid -----------------------------------------------------------------------

    /// The band appears on the whole library only; a filter or a search shows
    /// the games it finds and nothing else.
    private var showsBand: Bool {
        filter == .all && search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The game the band shows: the one under way, else the most recent.
    private var bandEntry: LibraryEntry? {
        session.liveEntry ?? entries.max { $0.updatedAt < $1.updatedAt }
    }

    private var shown: [LibraryEntry] {
        let words = search.split(separator: " ").map(String.init)
        let found = entries.filter { entry in
            filter.includes(entry)
                && words.allSatisfy { entry.searchText.localizedStandardContains($0) }
        }
        let sorted = found.sorted { order == .newest ? $0.updatedAt > $1.updatedAt : $0.updatedAt < $1.updatedAt }
        guard showsBand, let band = bandEntry else { return sorted }
        return sorted.filter { $0.id != band.id }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                // Three to a row at the window's usual width, fewer when it narrows.
                columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                if showsBand {
                    Section {
                        ForEach(shown) { card($0) }
                    } header: {
                        band.padding(.bottom, 0)
                    }
                } else {
                    ForEach(shown) { card($0) }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 40)
            if shown.isEmpty && !showsBand {
                Text("Aucune partie")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 60)
            }
        }
        .scrollIndicators(.never)
    }

    private func card(_ entry: LibraryEntry) -> some View {
        LibraryCard(entry: entry, action: action(for: entry), isEnabled: isReady) {
            session.open(entry)
        }
        .contextMenu {
            Button(action(for: entry)) { session.open(entry) }
                .disabled(!isReady)
            Button("Exporter en SGF…") { session.export(entry) }
            Divider()
            Button("Supprimer…", role: .destructive) { deleting = entry }
                .disabled(!session.canDelete(entry))
        }
    }

    private func action(for entry: LibraryEntry) -> String {
        if entry.canResume { return "Reprendre" }
        if session.isOnScreen(entry), session.state?.hasLiveGame == true { return "Reprendre" }
        return "Revoir"
    }

    // -- the band -------------------------------------------------------------------

    @ViewBuilder
    private var band: some View {
        if session.phase == .starting {
            LibraryBand(board: bandEntry?.finalBoard, kicker: "Démarrage de KataGo…", kickerColor: Theme.secondaryText,
                        title: bandEntry.map(LibraryText.bandTitle) ?? "Moyo",
                        detail: bandEntry.map(LibraryText.lastGameDetail) ?? "",
                        isStarting: true) {
                Button(bandEntry.map(action(for:)) ?? "Reprendre") {}
                    .buttonStyle(.glassProminent)
                    .disabled(true)
            }
        } else if let live = session.liveEntry {
            LibraryBand(board: liveBoard ?? live.finalBoard, kicker: "● Partie en cours", kickerColor: Theme.warning,
                        title: LibraryText.bandTitle(live),
                        detail: liveDetail(live)) {
                Button("Reprendre la partie") { session.open(live) }
                    .buttonStyle(.glassProminent)
                if session.state?.status == .playing {
                    Button("Abandonner") { session.requestResignation() }
                        .buttonStyle(.glass)
                }
            }
        } else if let last = bandEntry {
            LibraryBand(board: last.finalBoard, kicker: "Dernière partie", kickerColor: Theme.warning,
                        title: LibraryText.bandTitle(last),
                        detail: LibraryText.lastGameDetail(last)) {
                Button(action(for: last)) { session.open(last) }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    /// The board in the engine is fresher than the one last written.
    private var liveBoard: LibraryEntry.Board? {
        guard let state = session.state else { return nil }
        var cells = Array(repeating: Character("."), count: state.size * state.size)
        for stone in state.stones where stone.row < state.size && stone.col < state.size {
            cells[stone.row * state.size + stone.col] = stone.color == .black ? "b" : "w"
        }
        return LibraryEntry.Board(size: state.size, stones: String(cells))
    }

    private func liveDetail(_ entry: LibraryEntry) -> String {
        var parts: [String] = []
        if let color = entry.humanColor {
            parts.append("Vous jouez \(Theme.name(color).lowercased())")
        }
        parts.append("coup \(session.state?.moveCount ?? session.state?.moveNumber ?? entry.moveCount)")
        parts.append("commencée \(LibraryText.moment(entry.createdAt))")
        if let lead = session.currentLead, abs(lead) >= 0.05 {
            parts.append(LibraryText.lead(lead))
        }
        return parts.joined(separator: " · ")
    }

    // -- empty --------------------------------------------------------------------------

    private var emptyLibrary: some View {
        VStack(spacing: 14) {
            BoardThumbnail(board: .empty(size: 9))
                .frame(width: 120)
                .opacity(0.9)
            Text("Jouez votre première partie")
                .font(.system(size: 20, weight: .semibold))
            Text(
                session.phase == .starting
                    ? "Démarrage de KataGo…"
                    : "Chaque partie jouée contre KataGo, ouverte depuis un SGF ou suivie avec Kifu est gardée ici d'elle-même."
            )
            .font(.system(size: 13))
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            VStack(spacing: 8) {
                Button {
                    NotificationCenter.default.post(name: .moyoNewGameRequested, object: nil)
                } label: {
                    Text("Nouvelle partie").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(!isReady)
                Button {
                    NotificationCenter.default.post(name: .moyoOpenRecordRequested, object: nil)
                } label: {
                    Text("Ouvrir un SGF…").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button {
                    session.connectPhone()
                } label: {
                    Label("Suivre un goban avec Kifu", systemImage: "iphone").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(!isReady)
            }
            .controlSize(.large)
            .frame(width: 260)
            .padding(.top, 6)
        }
        .padding(36)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1))
        )
    }
}

// -- the filters ------------------------------------------------------------------------

enum LibraryFilter: String, Identifiable, Hashable {
    case all, ai, record, kifu, toResume, analysisIncomplete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Toutes les parties"
        case .ai: return "Contre KataGo"
        case .record: return "Révisées"
        case .kifu: return "Depuis Kifu"
        case .toResume: return "À reprendre"
        case .analysisIncomplete: return "Analyse incomplète"
        }
    }

    var dot: Color? {
        switch self {
        case .toResume: return Theme.connected
        case .analysisIncomplete: return Theme.warning
        default: return nil
        }
    }

    func includes(_ entry: LibraryEntry) -> Bool {
        switch self {
        case .all: return true
        case .ai: return entry.kind == .ai
        case .record: return entry.kind == .record
        case .kifu: return entry.kind == .kifu
        case .toResume: return entry.canResume
        case .analysisIncomplete: return entry.isAnalysisIncomplete
        }
    }
}

enum LibraryOrder: String, CaseIterable, Identifiable {
    case newest, oldest

    var id: String { rawValue }
    var label: String { self == .newest ? "Plus récentes" : "Plus anciennes" }
}

// -- the card ---------------------------------------------------------------------------

private struct LibraryCard: View {
    let entry: LibraryEntry
    let action: String
    let isEnabled: Bool
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            BoardThumbnail(board: entry.finalBoard)
                .frame(width: 112, height: 112)
                .padding(.leading, 12)
                .padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 0) {
                headline
                HStack(spacing: 5) {
                    if let color = entry.humanColor {
                        Circle()
                            .fill(Theme.stone(color))
                            .overlay(Circle().strokeBorder(color == .black ? Color.black : Color.gray, lineWidth: 1))
                            .frame(width: 10, height: 10)
                    }
                    Text("\(entry.displayTitle) · \(entry.origin)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)
                tags.padding(.top, 8)
                Spacer(minLength: 8)
                HStack(alignment: .bottom) {
                    // On one line when it fits, on two otherwise: the date and the
                    // length both matter more than a tidy line.
                    ViewThatFits(in: .horizontal) {
                        Text("\(LibraryText.day(entry.updatedAt)) · \(LibraryText.moves(entry.moveCount))")
                            .lineLimit(1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LibraryText.day(entry.updatedAt)).lineLimit(1)
                            Text(LibraryText.moves(entry.moveCount)).lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.35))
                    Spacer(minLength: 6)
                    Text(action)
                        .font(.system(size: 12, weight: isHovered ? .semibold : .regular))
                        .foregroundStyle(isHovered ? Color.black : Color.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            isHovered ? Color.white : Theme.tagBackground,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 136)
        .background(
            Color.white.opacity(isHovered ? 0.09 : 0.05),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(isHovered ? 0.18 : 0.07))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { isHovered = $0 && isEnabled }
        .onTapGesture { if isEnabled { open() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LibraryText.headline(entry))
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .lineLimit(1)
            if let note = LibraryText.outcome(entry) {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// As many tags as fit: the analysis first, then where the game comes from.
    private var tags: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                analysisTag
                originTag
            }
            HStack(spacing: 5) { analysisTag }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var analysisTag: some View {
        if let analysis = LibraryText.analysisTag(entry) {
            LibraryTag(text: analysis.text, color: analysis.color)
        }
    }

    @ViewBuilder private var originTag: some View {
        if entry.kind == .kifu { LibraryTag(text: "Kifu") }
        if entry.kind == .record { LibraryTag(text: "SGF importé") }
    }
}

private struct LibraryTag: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.tagBackground, in: Capsule())
    }
}

// -- the band -----------------------------------------------------------------------------

private struct LibraryBand<Actions: View>: View {
    let board: LibraryEntry.Board?
    let kicker: String
    let kickerColor: Color
    let title: String
    let detail: String
    var isStarting = false
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            BoardThumbnail(board: board ?? .empty(size: 19))
                .frame(width: 228, height: 228)
                .padding(.leading, 16)
                .opacity(board == nil ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if isStarting { ProgressView().controlSize(.mini) }
                    Text(kicker.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(kickerColor)
                }
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                HStack(spacing: 8) { actions }
                    .controlSize(.large)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                stops: [.init(color: Theme.wood.opacity(0.14), location: 0), .init(color: .clear, location: 0.6)],
                startPoint: .leading, endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .padding(.bottom, 16)
    }
}

// -- words ---------------------------------------------------------------------------------

/// What the library says about a game, in French, with French numbers.
enum LibraryText {
    static func count(_ count: Int) -> String {
        count == 1 ? "1 partie" : "\(count) parties"
    }

    static func moves(_ count: Int) -> String {
        count == 1 ? "1 coup" : "\(count) coups"
    }

    /// The large figure on a card: the result, or what stands in for it.
    static func headline(_ entry: LibraryEntry) -> String {
        if let result = entry.displayResult { return result }
        if entry.status == .inProgress { return "En cours" }
        return "Sans résultat"
    }

    static func outcome(_ entry: LibraryEntry) -> String? {
        if entry.status == .inProgress, entry.result == nil { return "coup \(entry.moveCount)" }
        return entry.won.map { $0 ? "gagnée" : "perdue" }
    }

    /// Where the analysis stands, for the kinds where it is a question: a record
    /// opened or a game followed. A game against KataGo is read as it is played.
    static func analysisTag(_ entry: LibraryEntry) -> (text: String, color: Color)? {
        switch entry.analysis {
        case .complete:
            return ("Analyse complète", .white)
        case .partial(let done, let total):
            guard entry.kind != .ai else { return nil }
            let percent = Int((Double(done) / Double(max(total, 1)) * 100).rounded())
            return ("Analyse \(percent) %", Theme.warning)
        case .none:
            guard entry.kind != .ai else { return nil }
            return ("Non analysée", Theme.secondaryText)
        }
    }

    static func bandTitle(_ entry: LibraryEntry) -> String {
        entry.kind == .ai ? "\(entry.displayTitle) · \(entry.origin)" : entry.displayTitle
    }

    static func lastGameDetail(_ entry: LibraryEntry) -> String {
        var parts: [String] = []
        if let result = entry.displayResult {
            parts.append(entry.won.map { "\(result), \($0 ? "gagnée" : "perdue")" } ?? result)
        } else if entry.status == .inProgress {
            parts.append("En cours")
        }
        if entry.kind != .ai { parts.append(entry.origin) }
        parts.append(moves(entry.moveCount))
        parts.append(day(entry.updatedAt))
        return parts.joined(separator: " · ")
    }

    /// The player's lead, from KataGo's reading.
    static func lead(_ lead: Double) -> String {
        let points = abs(lead)
        let figure = points.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
        let unit = points < 2 ? "point" : "points"
        return lead > 0
            ? "KataGo vous donne \(figure) \(unit) d'avance"
            : "KataGo vous donne \(figure) \(unit) de retard"
    }

    private static let french = Locale(identifier: "fr_FR")

    /// "Aujourd'hui", "Hier", "Mardi 17", "Lundi 2 novembre", "2 novembre 2025".
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Aujourd'hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Hier"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let format: Date.FormatStyle
        if days >= 0 && days <= 6 {
            format = Date.FormatStyle(locale: french, calendar: calendar).weekday(.wide).day()
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            format = Date.FormatStyle(locale: french, calendar: calendar).weekday(.wide).day().month(.wide)
        } else {
            format = Date.FormatStyle(locale: french, calendar: calendar).day().month(.wide).year()
        }
        let text = date.formatted(format)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "aujourd'hui à 21:05", "hier à 19:40", "mardi 17 à 12:15".
    static func moment(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(Date.FormatStyle(locale: french, calendar: calendar).hour().minute())
        return "\(day(date, now: now, calendar: calendar).lowercased()) à \(time)"
    }
}
