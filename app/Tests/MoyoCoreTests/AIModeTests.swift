import Foundation
import Testing

@testable import MoyoCore

@Suite("Modes de l'adversaire")
struct AIModeTests {
    @Test("Les modes connus ont un nom français")
    func knownModes() {
        #expect(AIMode.mode(for: "ai:human").name == "Modèle humain")
        #expect(AIMode.mode(for: "ai:default").name == "Pleine force")
        #expect(AIMode.mode(for: "ai:pro").name == "Style d'époque")
    }

    @Test("Un mode ajouté en amont reste affichable")
    func unknownModeStaysUsable() {
        let mode = AIMode.mode(for: "ai:newthing")
        #expect(mode.id == "ai:newthing")
        #expect(!mode.name.isEmpty)
        #expect(mode.setting == nil)
    }

    @Test("Seuls les modes réglables portent un contrôle")
    func onlySomeModesHaveASetting() {
        #expect(AIMode.mode(for: "ai:human").setting?.key == "human_kyu_rank")
        #expect(AIMode.mode(for: "ai:pro").setting?.key == "pro_year")
        #expect(AIMode.mode(for: "ai:p:rank").setting?.key == "kyu_rank")
        #expect(AIMode.mode(for: "ai:default").setting == nil)
        #expect(AIMode.mode(for: "ai:jigo").setting == nil)
    }

    @Test("Les rangs se lisent en kyu puis en dan, comme KaTrain les stocke")
    func rankWording() {
        let describe = AIMode.mode(for: "ai:human").setting!.describe
        #expect(describe(20) == "20 kyu")
        #expect(describe(1) == "1 kyu")
        #expect(describe(0) == "1 dan")
        #expect(describe(-8) == "9 dan")
    }

    @Test("Le tag dit le niveau nu, et nomme tout autre réglage")
    func tag() {
        #expect(AIMode.mode(for: "ai:human").tag(for: 8) == "8 kyu")
        #expect(AIMode.mode(for: "ai:pro").tag(for: 1950) == "époque 1950")
        #expect(AIMode.mode(for: "ai:scoreloss").tag(for: 0.5) == "faiblesse 0,50")
        #expect(AIMode.mode(for: "ai:default").tag(for: 3) == nil)
        #expect(AIMode.mode(for: "ai:human").tag(for: nil) == nil)
    }

    @Test("Le rang humain couvre du débutant au haut niveau")
    func humanRankRange() {
        let setting = AIMode.mode(for: "ai:human").setting!
        #expect(setting.range == -8...20)
        #expect(setting.step == 1)
    }

    @Test("L'époque professionnelle se lit en années")
    func proYearWording() {
        #expect(AIMode.mode(for: "ai:pro").setting!.describe(1950) == "1950")
    }

    @Test("Le catalogue couvre l'ordre recommandé de KaTrain")
    func catalogueCoversKaTrain() {
        // The identifiers KaTrain lists in AI_STRATEGIES_RECOMMENDED_ORDER.
        let upstream = [
            "ai:default", "ai:human", "ai:pro", "ai:p:rank", "ai:handicap", "ai:simple",
            "ai:scoreloss", "ai:policy", "ai:p:weighted", "ai:jigo", "ai:antimirror",
            "ai:p:pick", "ai:p:local", "ai:p:tenuki", "ai:p:territory", "ai:p:influence",
        ]
        for identifier in upstream {
            #expect(AIMode.catalogue[identifier] != nil, "mode manquant : \(identifier)")
        }
    }
}

@Suite("Valeurs de réglage hétérogènes")
struct SettingValueTests {
    private func decode(_ json: String) throws -> [String: SettingValue] {
        try JSONDecoder().decode([String: SettingValue].self, from: Data(json.utf8))
    }

    @Test("Nombres, booléens et textes cohabitent")
    func mixedTypes() throws {
        let values = try decode(#"{"human_kyu_rank":8,"modern_style":false,"note":"x","strength":0.2}"#)
        #expect(values["human_kyu_rank"]?.doubleValue == 8)
        #expect(values["strength"]?.doubleValue == 0.2)
        #expect(values["modern_style"] == .flag(false))
        #expect(values["note"] == .text("x"))
    }

    @Test("Un booléen n'est pas pris pour un nombre")
    func booleanIsNotANumber() throws {
        let values = try decode(#"{"automatic":true}"#)
        #expect(values["automatic"]?.doubleValue == nil)
        #expect(values["automatic"] == .flag(true))
    }
}
