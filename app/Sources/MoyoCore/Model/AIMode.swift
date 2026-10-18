import Foundation

/// How an AI mode is presented, and which of its settings is worth a control.
///
/// KaTrain exposes dozens of knobs per mode. Only the one that actually changes how
/// the opponent feels gets a slider here; the rest keep the values from
/// `~/.katrain/config.json`, shared with KaTrain itself.
public struct AIMode: Identifiable, Sendable {
    public struct Setting: Sendable {
        public let key: String
        public let label: String
        public let range: ClosedRange<Double>
        public let step: Double
        public let describe: @Sendable (Double) -> String
    }

    public let id: String
    public let name: String
    public let summary: String
    public let setting: Setting?

    /// The setting as a tag next to the name: "8 kyu", "époque 1950". A rank needs
    /// no label, it is one; anything else says what the figure is.
    public func tag(for value: Double?) -> String? {
        guard let setting, let value else { return nil }
        let figure = setting.describe(value)
        return setting.label == "Niveau" ? figure : "\(setting.label.lowercased()) \(figure)"
    }

    /// Ranks run from 20 kyu up through the dan grades, the way KaTrain stores them:
    /// positive is kyu, zero and below is dan.
    @Sendable static func rank(_ value: Double) -> String {
        let step = Int(value.rounded())
        return step > 0 ? "\(step) kyu" : "\(1 - step) dan"
    }

    static let humanRank = Setting(
        key: "human_kyu_rank",
        label: "Niveau",
        range: -8...20,
        step: 1,
        describe: rank
    )

    static let calibratedRank = Setting(
        key: "kyu_rank",
        label: "Niveau",
        range: -2...15,
        step: 1,
        describe: rank
    )

    static let proYear = Setting(
        key: "pro_year",
        label: "Époque",
        range: 1800...2023,
        step: 1,
        describe: { String(Int($0.rounded())) }
    )

    static let strength = Setting(
        key: "strength",
        label: "Faiblesse",
        range: 0...1,
        step: 0.05,
        describe: { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") }
    )

    /// Keyed by KaTrain's own identifier. Modes it adds later fall back to a readable
    /// name derived from the identifier rather than disappearing from the list.
    public static let catalogue: [String: AIMode] = [
        "ai:default": AIMode(
            id: "ai:default", name: "Pleine force",
            summary: "KataGo sans retenue.", setting: nil
        ),
        "ai:human": AIMode(
            id: "ai:human", name: "Modèle humain",
            summary: "Joue comme un joueur de ce niveau, pas comme une machine bridée.",
            setting: humanRank
        ),
        "ai:pro": AIMode(
            id: "ai:pro", name: "Style d'époque",
            summary: "Imite le jeu professionnel d'une année donnée.", setting: proYear
        ),
        "ai:p:rank": AIMode(
            id: "ai:p:rank", name: "Niveau calibré",
            summary: "Force réglée pour correspondre à un rang.", setting: calibratedRank
        ),
        "ai:handicap": AIMode(
            id: "ai:handicap", name: "Handicap",
            summary: "S'adapte à une partie à handicap.", setting: nil
        ),
        "ai:simple": AIMode(
            id: "ai:simple", name: "Jeu simple",
            summary: "Cherche les positions calmes et stables.", setting: nil
        ),
        "ai:scoreloss": AIMode(
            id: "ai:scoreloss", name: "Perte de points",
            summary: "Se relâche d'autant plus que le réglage est haut.", setting: strength
        ),
        "ai:policy": AIMode(
            id: "ai:policy", name: "Intuition brute",
            summary: "Joue son premier réflexe, sans réfléchir.", setting: nil
        ),
        "ai:p:weighted": AIMode(
            id: "ai:p:weighted", name: "Intuition pondérée",
            summary: "Tire au sort parmi ses réflexes.", setting: nil
        ),
        "ai:jigo": AIMode(
            id: "ai:jigo", name: "Au demi-point",
            summary: "Cherche à gagner de justesse.", setting: nil
        ),
        "ai:antimirror": AIMode(
            id: "ai:antimirror", name: "Anti-miroir",
            summary: "Punit le jeu en miroir.", setting: nil
        ),
        "ai:p:pick": AIMode(
            id: "ai:p:pick", name: "Coups échantillonnés",
            summary: "N'examine qu'une poignée de coups.", setting: nil
        ),
        "ai:p:local": AIMode(
            id: "ai:p:local", name: "Jeu local",
            summary: "Répond toujours près du dernier coup.", setting: nil
        ),
        "ai:p:tenuki": AIMode(
            id: "ai:p:tenuki", name: "Tenuki",
            summary: "Délaisse volontiers le combat en cours.", setting: nil
        ),
        "ai:p:territory": AIMode(
            id: "ai:p:territory", name: "Territoire",
            summary: "Joue bas et prend les points.", setting: nil
        ),
        "ai:p:influence": AIMode(
            id: "ai:p:influence", name: "Influence",
            summary: "Joue haut et construit vers le centre.", setting: nil
        ),
    ]

    public static func mode(for identifier: String) -> AIMode {
        catalogue[identifier] ?? AIMode(
            id: identifier,
            name: identifier.replacingOccurrences(of: "ai:", with: "").capitalized,
            summary: "",
            setting: nil
        )
    }
}
