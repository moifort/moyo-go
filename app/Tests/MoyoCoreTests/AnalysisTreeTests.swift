import Foundation
import Testing

@testable import MoyoCore

/// The analysis: the toggle, the tree the bridge sends, and its layout in columns.
@MainActor
@Suite("Analyse et arbre des variantes")
struct AnalysisTreeTests {
    private static let ready = BridgeEvent.ready(katago: nil, model: nil, strategies: [], settings: [:])

    private func session() -> GameSession {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let session = GameSession(store: SettingsStore(defaults: defaults, key: "test.settings"))
        session.handle(Self.ready)
        return session
    }

    private func state(_ fields: String) throws -> GameState {
        let line = """
            {"event":"state","id":1,"size":9,"stones":[],"to_play":"B","move_number":2,\
            "last_move":null,"captures":{"by_black":0,"by_white":0},"score_history":[null,null,null],\
            "human_color":"B","result":null,\(fields)}
            """
        guard case .state(_, let state) = try BridgeEvent.decode(line: line) else {
            throw CancellationError()
        }
        return state
    }

    /// The game down to move 3, and a branch of two stones from move 1.
    private static let nodes = [
        TreeNode(id: 1, parent: nil, color: nil, origin: .game),
        TreeNode(id: 2, parent: 1, color: .black, row: 4, col: 4, origin: .game),
        TreeNode(id: 5, parent: 2, color: .white, row: 0, col: 0, origin: .analysis),
        TreeNode(id: 3, parent: 2, color: .white, row: 2, col: 2, origin: .game),
        TreeNode(id: 4, parent: 3, color: .black, row: 6, col: 6, origin: .game),
        TreeNode(id: 6, parent: 5, color: .black, pass: true, origin: .analysis),
    ]

    @Test("L'événement tree se décode, passe comprise")
    func decodesTree() throws {
        let line = """
            {"event":"tree","nodes":[\
            {"id":1,"parent":null,"color":null,"row":null,"col":null,"pass":false,"origin":"game"},\
            {"id":2,"parent":1,"color":"B","row":3,"col":4,"pass":false,"origin":"analysis"},\
            {"id":3,"parent":2,"color":"W","row":null,"col":null,"pass":true,"origin":"preview"}]}
            """
        guard case .tree(let nodes) = try BridgeEvent.decode(line: line) else {
            Issue.record("attendu un événement tree")
            return
        }
        #expect(nodes.count == 3)
        #expect(nodes[1] == TreeNode(id: 2, parent: 1, color: .black, row: 3, col: 4, origin: .analysis))
        #expect(nodes[2].pass)
        #expect(nodes[2].origin == .preview)
    }

    @Test("Une partie mise de côté se lit en analyse, avec la partie à retrouver")
    func liveGameInAnalysis() throws {
        let state = try state(#""status":"playing","view":"analysis","node_id":5,"live_node_id":3"#)
        #expect(state.isAnalysing)
        #expect(state.hasLiveGame)
        #expect(!state.isReviewing)
        #expect(state.liveNodeId == 3)
    }

    @Test("Un pont plus ancien, sans vue, se lit comme avant")
    func olderBridge() throws {
        let state = try state(#""status":"playing""#)
        #expect(!state.isAnalysing)
        #expect(state.view == nil)
    }

    @Test("La partie occupe la première colonne, la variante la suivante")
    func layoutColumns() {
        let layout = TreeLayout(nodes: Self.nodes)
        #expect(layout.slot(of: 1) == .init(row: 0, column: 0))
        #expect(layout.slot(of: 3) == .init(row: 2, column: 0))
        #expect(layout.slot(of: 4) == .init(row: 3, column: 0))
        // Played before the game's own move, the branch still steps aside.
        #expect(layout.slot(of: 5) == .init(row: 2, column: 1))
        #expect(layout.slot(of: 6) == .init(row: 3, column: 1))
        #expect(layout.rows == 4)
        #expect(layout.columns == 2)
        #expect(layout.edges.contains(.init(from: .init(row: 1, column: 0), to: .init(row: 2, column: 1), origin: .analysis)))
    }

    @Test("Deux variantes qui se chevauchent ne partagent pas une colonne")
    func layoutAvoidsOverlap() {
        let nodes = Self.nodes + [
            TreeNode(id: 7, parent: 3, color: .black, row: 8, col: 8, origin: .analysis),
            TreeNode(id: 8, parent: 1, color: .black, row: 1, col: 1, origin: .analysis),
            TreeNode(id: 9, parent: 8, color: .white, row: 1, col: 2, origin: .analysis),
            TreeNode(id: 10, parent: 9, color: .black, row: 1, col: 3, origin: .analysis),
        ]
        let layout = TreeLayout(nodes: nodes)
        let spans = layout.placed.reduce(into: [Int: [Int]]()) { $0[$1.column, default: []].append($1.row) }
        for rows in spans.values {
            #expect(Set(rows).count == rows.count)
        }
        // The branch from the root runs over rows 1 to 3, where the first branch sits.
        #expect(layout.slot(of: 8)!.column != layout.slot(of: 5)!.column)
    }

    @Test("Le nœud affiché dit s'il est dans une variante et s'il peut être retiré")
    func currentNode() throws {
        let session = session()
        session.handle(.tree(Self.nodes))
        session.handle(.state(id: nil, try state(#""status":"review","view":"analysis","node_id":6,"move_count":3"#)))
        #expect(session.isInBranch)
        #expect(session.isOnLeafOfAnalysis)
        #expect(session.canUndo)
        #expect(session.isDeletable(5))
        #expect(!session.isDeletable(3))
        #expect(!session.canStepForward)
        session.handle(.state(id: nil, try state(#""status":"review","view":"analysis","node_id":3,"move_count":3"#)))
        #expect(!session.isInBranch)
        #expect(session.hasPreviousSibling)
        #expect(!session.hasNextSibling)
        #expect(session.canStepForward)
        // A fork: ↓ goes down the branch it opens.
        session.handle(.state(id: nil, try state(#""status":"review","view":"analysis","node_id":2,"move_count":3"#)))
        #expect(session.hasNextSibling)
    }

    @Test("Le sélecteur n'existe que s'il y a une partie à retrouver, décompte compris")
    func toggle() throws {
        let session = session()
        session.handle(.state(id: nil, try state(#""status":"review","view":"analysis""#)))
        #expect(!session.canSwitchView)
        session.handle(.state(id: nil, try state(#""status":"following","view":"live""#)))
        #expect(session.canSwitchView)
        #expect(session.canPlace)
        session.handle(.state(id: nil, try state(#""status":"scoring","view":"live""#)))
        #expect(session.canSwitchView)
    }

    @Test("Dans une variante, le score est celui de la position, pas celui de la courbe")
    func leadInBranch() throws {
        let session = session()
        session.handle(.tree(Self.nodes))
        session.handle(.score(moveNumber: 2, scoreLead: 5))
        session.handle(
            .state(id: nil, try state(#""status":"review","view":"analysis","node_id":5,"move_count":3,"score_lead":-3"#))
        )
        #expect(session.currentLead == -3)
    }
}
