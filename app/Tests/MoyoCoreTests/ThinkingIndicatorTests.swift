import Testing

@testable import MoyoCore

@Suite("Temporisation de l'indicateur de réflexion")
@MainActor
struct ThinkingIndicatorTests {
    /// Real durations, shortened so the suite stays quick while keeping the same
    /// ratios as the shipped values.
    private func indicator() -> ThinkingIndicator {
        let indicator = ThinkingIndicator()
        indicator.appearAfter = .milliseconds(100)
        indicator.minimumVisible = .milliseconds(80)
        return indicator
    }

    @Test("Une réflexion brève n'affiche jamais rien")
    func shortThinkingStaysInvisible() async throws {
        let indicator = indicator()
        indicator.began()
        try await Task.sleep(for: .milliseconds(40))
        indicator.ended()
        #expect(!indicator.isVisible)
        try await Task.sleep(for: .milliseconds(120))
        #expect(!indicator.isVisible)
    }

    @Test("Une réflexion longue finit par s'afficher")
    func longThinkingBecomesVisible() async throws {
        let indicator = indicator()
        indicator.began()
        #expect(!indicator.isVisible)
        try await Task.sleep(for: .milliseconds(160))
        #expect(indicator.isVisible)
    }

    @Test("Une fois affiché, il ne clignote pas")
    func staysVisibleForAMoment() async throws {
        let indicator = indicator()
        indicator.began()
        try await Task.sleep(for: .milliseconds(130))
        #expect(indicator.isVisible)
        indicator.ended()
        #expect(indicator.isVisible)  // still up: it has only just appeared
        try await Task.sleep(for: .milliseconds(120))
        #expect(!indicator.isVisible)
    }

    @Test("Il disparaît immédiatement s'il est resté assez longtemps")
    func hidesAtOnceWhenAlreadyShownLongEnough() async throws {
        let indicator = indicator()
        indicator.began()
        // Waits for the indicator to appear, then for longer than its minimum: a
        // fixed 250 ms failed on the Xcode 27 runner, where the timer woke the
        // appearance late enough that it had been up for less than the minimum.
        while !indicator.isVisible {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(160))
        indicator.ended()
        #expect(!indicator.isVisible)
    }

    @Test("Une nouvelle réflexion annule une disparition en attente")
    func newThinkingCancelsPendingHide() async throws {
        let indicator = indicator()
        indicator.began()
        try await Task.sleep(for: .milliseconds(130))
        indicator.ended()
        indicator.began()
        try await Task.sleep(for: .milliseconds(120))
        #expect(indicator.isVisible)
    }
}
