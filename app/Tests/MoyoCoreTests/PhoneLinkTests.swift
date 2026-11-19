import Foundation
import Testing

@testable import MoyoCore

/// The link to the phone recovers from what the local network throws at it.
@MainActor
@Suite("Lien avec le téléphone")
struct PhoneLinkTests {
    @Test("Une recherche en échec est abandonnée, pour que « Réessayer » en relance une")
    func failedSearchIsDropped() {
        let link = PhoneLink()
        link.startDiscovery()
        #expect(link.isSearching)
        link.searchFailed("Réseau local refusé")
        #expect(!link.isSearching)
        #expect(link.status == .failed("Réseau local refusé"))
        link.startDiscovery()
        #expect(link.isSearching)
        link.searchFailed("fin du test")
    }

    @Test("Un pair qui n'envoie jamais de saut de ligne ne fait pas grossir le tampon sans fin")
    func bufferIsCapped() {
        let link = PhoneLink()
        link.consume(Data(repeating: UInt8(ascii: "x"), count: 2 * 1_024 * 1_024))
        #expect(link.bufferedBytes <= PhoneLink.maximumLine)
        link.consume(Data(#"{"size":3,"rows":["X..","...","..O"],"status":"locked"}"#.utf8 + [0x0A]))
        #expect(link.latest?.size == 3)
    }
}
