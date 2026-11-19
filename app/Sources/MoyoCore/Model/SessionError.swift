import Foundation

/// Something went wrong, said to the player: under which title, in which words.
///
/// The bridge owns the rules and says what it refused with a `code`; the words are
/// the app's. Its own message is meant for the log, half of it in English, and an
/// internal one is a Python exception — neither is shown.
public struct SessionError: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A record that will not open.
        case opening
        /// The analysis could not be written back to the record's file.
        case saving
        /// The bridge said no to what the player asked.
        case refused
        /// Something broke in the engine or between the app and it.
        case engine
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var title: String {
        switch kind {
        case .opening: return "Cette partie n'a pas pu être ouverte"
        case .saving: return "L'analyse n'a pas pu être enregistrée"
        case .refused: return "Action impossible"
        case .engine: return "Erreur du moteur"
        }
    }

    /// Refusals the board answers on its own, without a word: an illegal move simply
    /// does not land, a variation asked for before its analysis has come back simply
    /// does not move, and a key pressed a moment too early — before the AI has
    /// answered, on a node just taken away, while a count is being settled — is not
    /// worth a dialog. `not_following` is a position the phone sent just as
    /// following stopped.
    static let silentCodes: Set<String> = [
        "illegal_move", "no_variation", "not_following", "nothing_to_undo", "no_node", "not_now", "not_your_turn",
    ]

    /// What the player reads for each code the bridge raises.
    private static let texts: [String: (Kind, String)] = [
        "bad_sgf": (.opening, "Le fichier n'est pas un SGF lisible, ou décrit un plateau que Moyo ne gère pas : seuls les plateaux carrés le sont."),
        "not_playing": (.refused, "La partie n'est plus en cours."),
        "not_scoring": (.refused, "La partie n'est pas en cours de décompte."),
        "no_group": (.refused, "Il n'y a pas de pierre à cet endroit."),
        "not_reviewing": (.refused, "Aucune analyse n'est ouverte."),
        "no_live_game": (.refused, "Aucune partie n'est en cours."),
        "no_game": (.refused, "Aucune partie n'est en cours."),
        "not_analysis_node": (.refused, "Seule une variante ajoutée en analyse peut être supprimée."),
        "unknown_ai": (.refused, "Ce mode d'IA n'est pas disponible dans cette installation."),
        "bad_board": (.refused, "La position envoyée par le téléphone n'a pas la taille de la partie suivie."),
        "no_engine": (.engine, "KataGo n'est pas encore prêt. Réessayez dans un instant."),
    ]

    /// Every code the app knows, silent or not.
    static var knownCodes: Set<String> { silentCodes.union(texts.keys) }

    /// For anything else — `internal`, a malformed command, a code newer than the app.
    private static let generic =
        "KataGo a rencontré une erreur inattendue. La partie continue ; le détail est dans le journal du moteur."

    /// The error to show for a bridge failure, or nil when it is one of the silent ones.
    public static func fromBridge(code: String, message: String) -> SessionError? {
        if silentCodes.contains(code) { return nil }
        guard let (kind, text) = texts[code] else { return SessionError(kind: .engine, message: generic) }
        return SessionError(kind: kind, message: text)
    }
}
