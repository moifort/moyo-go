import SwiftUI

/// Draws the board and reports clicks. Holds no rules and no state of its own.
public struct BoardView: View {
    public let state: GameState
    public let isInteractive: Bool
    public let onPlay: (Point) -> Void

    /// The intersection under the pointer, for the caption of a proposed move.
    @State private var hovered: Point?

    public init(state: GameState, isInteractive: Bool, onPlay: @escaping (Point) -> Void) {
        self.state = state
        self.isInteractive = isInteractive
        self.onPlay = onPlay
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let geometry = BoardGeometry(size: state.size, side: side)

            ZStack {
                Canvas { context, _ in
                    draw(in: &context, geometry: geometry)
                }
                .frame(width: side, height: side)
                .background(Theme.wood)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.015, style: .continuous))
                // A Canvas draws but does not take part in hit testing, so clicks are
                // caught by an explicit shape laid over it. Drawing and interaction
                // stay separate.
                .overlay {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture(coordinateSpace: .local)
                                .onEnded { tap in
                                    guard isInteractive,
                                        let point = geometry.intersection(at: tap.location)
                                    else { return }
                                    onPlay(point)
                                }
                        )
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case .active(let location): hovered = geometry.intersection(at: location)
                            case .ended: hovered = nil
                            }
                        }
                }
                .overlay {
                    if let hovered, let caption = state.proposalCaption(at: hovered) {
                        captionView(caption, at: hovered, geometry: geometry)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Goban \(state.size) sur \(state.size)")
                .accessibilityValue(accessibilityValue)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// A small dark label just above the disc, below it on the top rows where above
    /// would leave the board. It never takes the pointer, so the hover holds.
    private func captionView(_ text: String, at point: Point, geometry: BoardGeometry) -> some View {
        let center = geometry.position(of: point)
        let offset = geometry.stoneRadius * 2.1
        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.windowBackground.opacity(0.92)))
            .fixedSize()
            .position(x: center.x, y: point.row < 2 ? center.y + offset : center.y - offset)
            .allowsHitTesting(false)
    }

    private var accessibilityValue: String {
        var description = "\(state.stones.count) pierres, coup \(state.moveNumber)"
        if let count = state.moveCount {
            description += " sur \(count)"
        }
        if state.bestMove != nil {
            description += ", meilleur coup proposé"
        }
        if state.localMove != nil {
            description += ", coup local proposé"
        }
        return description
    }

    private func draw(in context: inout GraphicsContext, geometry: BoardGeometry) {
        if let zone = state.localZone {
            drawLocalZone(in: &context, geometry: geometry, zone: zone)
        }
        drawGrid(in: &context, geometry: geometry)
        drawStarPoints(in: &context, geometry: geometry)
        drawStones(in: &context, geometry: geometry)
        if let scoring = state.scoring {
            drawTerritory(in: &context, geometry: geometry, scoring: scoring)
        } else {
            drawLastMove(in: &context, geometry: geometry)
        }
        if let nearby = state.localMove, nearby.point != state.bestMove?.point {
            drawProposal(in: &context, geometry: geometry, at: nearby.point, color: Theme.localMove)
        }
        if let best = state.bestMove {
            drawProposal(in: &context, geometry: geometry, at: best.point, color: Theme.bestMove)
            if state.localMove?.point == best.point {
                drawLocalRing(in: &context, geometry: geometry, at: best.point)
            }
        }
    }

    /// The zone the local reading is kept in, washed under the grid.
    ///
    /// Half a cell past its outer lines, so the stones on its edge sit inside it.
    /// Faint on purpose: it says where the reading looks, and the board stays the
    /// thing being read.
    private func drawLocalZone(in context: inout GraphicsContext, geometry: BoardGeometry, zone: LocalZone) {
        let topLeft = geometry.position(row: zone.top, col: zone.left)
        let bottomRight = geometry.position(row: zone.bottom, col: zone.right)
        let inset = geometry.stoneRadius * 1.05
        let rect = CGRect(
            x: topLeft.x - inset, y: topLeft.y - inset,
            width: bottomRight.x - topLeft.x + inset * 2,
            height: bottomRight.y - topLeft.y + inset * 2
        )
        let path = Path(roundedRect: rect, cornerRadius: geometry.stoneRadius * 0.5)
        context.fill(path, with: .color(Theme.localMove.opacity(0.10)))
        context.stroke(
            path,
            with: .color(Theme.localMove.opacity(0.55)),
            style: StrokeStyle(lineWidth: max(1, geometry.lineWidth * 1.5), dash: [geometry.stoneRadius * 0.4])
        )
    }

    /// When the best move is already the local one, a blue ring around the green
    /// disc says so without hiding either.
    private func drawLocalRing(in context: inout GraphicsContext, geometry: BoardGeometry, at point: Point) {
        let center = geometry.position(of: point)
        let radius = geometry.stoneRadius * 1.0
        let rect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(Theme.localMove),
            lineWidth: max(1.2, geometry.stoneRadius * 0.16)
        )
    }

    /// A proposed move — KataGo's first choice, or the local one — drawn last so
    /// nothing sits on top of it.
    ///
    /// A full disc rather than a ring: the point is to see a move, not a mark. The
    /// bridge only ever sends an empty intersection, so it can never cover a stone.
    private func drawProposal(
        in context: inout GraphicsContext,
        geometry: BoardGeometry,
        at point: Point,
        color: Color
    ) {
        let center = geometry.position(of: point)
        let radius = geometry.stoneRadius
        let rect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(color.opacity(0.92)))
        // The wood and the green are close in value; a darker edge keeps the disc
        // from melting into the board at small sizes.
        context.stroke(
            path,
            with: .color(Theme.gridLine.opacity(0.4)),
            lineWidth: max(0.6, radius * 0.06)
        )
    }

    /// Territory as small squares on the empty points, in the colour that owns them.
    private func drawTerritory(
        in context: inout GraphicsContext,
        geometry: BoardGeometry,
        scoring: ScoringDetail
    ) {
        let side = geometry.stoneRadius * 0.44
        for owned in scoring.points {
            let center = geometry.position(row: owned.row, col: owned.col)
            let rect = CGRect(
                x: center.x - side / 2, y: center.y - side / 2,
                width: side, height: side
            )
            let path = Path(roundedRect: rect, cornerRadius: side * 0.3)
            context.fill(path, with: .color(Theme.stone(owned.color)))
            // White territory on light wood needs an edge to stay legible.
            if owned.color == .white {
                context.stroke(path, with: .color(Theme.gridLine.opacity(0.45)), lineWidth: 0.6)
            }
        }
    }

    private func drawGrid(in context: inout GraphicsContext, geometry: BoardGeometry) {
        var path = Path()
        let last = geometry.size - 1
        for index in 0...last {
            let start = geometry.position(row: index, col: 0)
            let end = geometry.position(row: index, col: last)
            path.move(to: start)
            path.addLine(to: end)

            let top = geometry.position(row: 0, col: index)
            let bottom = geometry.position(row: last, col: index)
            path.move(to: top)
            path.addLine(to: bottom)
        }
        context.stroke(path, with: .color(Theme.gridLine), lineWidth: geometry.lineWidth)
    }

    private func drawStarPoints(in context: inout GraphicsContext, geometry: BoardGeometry) {
        for point in geometry.starPoints {
            let center = geometry.position(of: point)
            let radius = geometry.starRadius
            let rect = CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(Theme.gridLine))
        }
    }

    private func drawStones(in context: inout GraphicsContext, geometry: BoardGeometry) {
        let radius = geometry.stoneRadius
        let dead = state.scoring?.deadPoints ?? []
        for stone in state.stones {
            let center = geometry.position(row: stone.row, col: stone.col)
            let rect = CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )
            let colour = Theme.stone(stone.color)
            let path = Path(ellipseIn: rect)
            guard dead.contains(stone.point) else {
                context.fill(path, with: .color(colour))
                continue
            }
            // A dead stone is dimmed, not emptied: it has to stay recognisably black
            // or white. What marks it as given up is the opponent's territory mark,
            // drawn over it once the point is counted.
            context.fill(path, with: .color(colour.opacity(Theme.deadStoneOpacity)))
            if stone.color == .white {
                context.stroke(
                    path,
                    with: .color(Theme.deadStoneContour),
                    lineWidth: max(0.6, radius * 0.05)
                )
            }
        }
    }

    private func drawLastMove(in context: inout GraphicsContext, geometry: BoardGeometry) {
        guard let last = state.lastMove,
            let stone = state.stones.first(where: { $0.row == last.row && $0.col == last.col })
        else { return }
        let center = geometry.position(of: last)
        let radius = geometry.stoneRadius * 0.44
        let rect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(Theme.lastMoveMarker(on: stone.color)),
            lineWidth: max(0.8, geometry.stoneRadius * 0.10)
        )
    }
}
