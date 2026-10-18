import Foundation

extension GameState {
    /// What a proposed move is, said when the pointer rests on it.
    ///
    /// The sidebar used to carry a legend for both colours; the board says it in
    /// place instead, on the one disc the player is looking at. nil anywhere else,
    /// stones and empty points alike. `showingLocal` false leaves the blue disc out,
    /// as the board does until Option is held.
    public func proposalCaption(at point: Point, showingLocal: Bool = true) -> String? {
        let best = bestMove?.point == point
        let nearby = showingLocal && localMove?.point == point
        guard best || nearby else { return nil }
        if let depth = variationDepth, depth > 0 {
            return variationKind == .local
                ? "Coup suivant de la séquence locale"
                : "Coup suivant de la proposition de KataGo"
        }
        if best && nearby { return "Meilleur coup selon KataGo, et meilleur coup local" }
        if best { return "Meilleur coup selon KataGo" }
        if let cost = localMove?.costLabel { return "Meilleur coup local, \(cost)" }
        return "Meilleur coup local"
    }
}
