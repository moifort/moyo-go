import SwiftUI

/// The tree of variations in the sidebar: the game down the first column, each
/// branch to its right from the move it answers, the position on screen ringed.
///
/// A click goes to a position; a right click on a stone placed by hand offers to
/// delete it and what follows. The tree scrolls on its own, inside a bounded height,
/// so the buttons under it stay where the hand expects them, and it keeps the
/// position on screen in view as the arrows move it.
struct VariationTree: View {
    let layout: TreeLayout
    let currentID: Int?
    let liveID: Int?
    let onSelect: (Int) -> Void
    let canDelete: (Int) -> Bool
    let onDelete: (Int) -> Void

    static let rowHeight: CGFloat = 18
    static let columnWidth: CGFloat = 16
    static let gutter: CGFloat = 30
    static let stone: CGFloat = 10
    /// Enough to see a fight unfold before scrolling, short enough to leave the
    /// buttons below in reach on a laptop screen.
    static let maxHeight: CGFloat = 280

    private var contentSize: CGSize {
        CGSize(
            width: Self.gutter + CGFloat(max(layout.columns, 1)) * Self.columnWidth + 6,
            height: CGFloat(max(layout.rows, 1)) * Self.rowHeight
        )
    }

    /// Where the tree is scrolled to, set by hand: the sidebar scrolls too, and a
    /// `ScrollViewReader` inside it never moved this one.
    @State private var position = ScrollPosition()
    /// The visible part of the tree, once laid out.
    @State private var viewport: CGSize = .zero

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in drawEdges(in: &context) }
                moveNumbers
                ForEach(layout.placed) { placed in
                    node(placed)
                        .position(center(row: placed.row, column: placed.column))
                }
            }
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
        }
        .scrollPosition($position)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentSize.height, Self.maxHeight))
        .onScrollGeometryChange(for: CGSize.self) { $0.containerSize } action: { _, size in
            let first = viewport == .zero
            viewport = size
            if first { reveal(animated: false) }
        }
        .onChange(of: revealKey) { reveal(animated: true) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Arbre des variantes")
    }

    /// What moves the position on screen out of view: another node, or a tree that
    /// grew or narrowed around it — a move of KataGo's line opens a column.
    private struct RevealKey: Equatable {
        let id: Int?
        let rows: Int
        let columns: Int
    }

    private var revealKey: RevealKey {
        RevealKey(id: currentID, rows: layout.rows, columns: layout.columns)
    }

    /// Puts the position on screen in the middle of the tree's area, as far as the
    /// edges of the tree allow.
    private func reveal(animated: Bool) {
        guard let id = currentID, let slot = layout.slot(of: id), viewport != .zero else { return }
        let target = center(row: slot.row, column: slot.column)
        let point = CGPoint(
            x: min(max(target.x - viewport.width / 2, 0), max(contentSize.width - viewport.width, 0)),
            y: min(max(target.y - viewport.height / 2, 0), max(contentSize.height - viewport.height, 0))
        )
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { position.scrollTo(point: point) }
        } else {
            position.scrollTo(point: point)
        }
    }

    private func center(row: Int, column: Int) -> CGPoint {
        CGPoint(
            x: Self.gutter + (CGFloat(column) + 0.5) * Self.columnWidth,
            y: (CGFloat(row) + 0.5) * Self.rowHeight
        )
    }

    /// Every fifth move numbered, and the move on screen, so the column reads like
    /// a ruler without a figure on every line.
    private var moveNumbers: some View {
        let current = currentID.flatMap { layout.slot(of: $0)?.row }
        return ForEach(0..<max(layout.rows, 1), id: \.self) { row in
            if row > 0, row % 5 == 0 || row == current {
                Text("\(row)")
                    .font(.system(size: 9, weight: row == current ? .semibold : .regular))
                    .foregroundStyle(row == current ? Theme.primaryText : Theme.secondaryText)
                    .monospacedDigit()
                    .frame(width: Self.gutter - 6, alignment: .trailing)
                    .position(x: (Self.gutter - 6) / 2, y: (CGFloat(row) + 0.5) * Self.rowHeight)
            }
        }
    }

    private func drawEdges(in context: inout GraphicsContext) {
        for edge in layout.edges {
            let from = center(row: edge.from.row, column: edge.from.column)
            let to = center(row: edge.to.row, column: edge.to.column)
            var path = Path()
            path.move(to: from)
            if edge.from.column == edge.to.column {
                path.addLine(to: to)
            } else {
                path.addQuadCurve(to: to, control: CGPoint(x: to.x, y: from.y))
            }
            let style = StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: edge.origin == .preview ? [2, 2.5] : [])
            context.stroke(path, with: .color(Self.edgeColor(edge.origin)), style: style)
        }
    }

    static func edgeColor(_ origin: TreeNode.Origin) -> Color {
        switch origin {
        case .game: Theme.secondaryText
        case .record: Theme.secondaryText.opacity(0.6)
        case .analysis: Theme.localMove
        case .preview: Theme.bestMove
        }
    }

    private func node(_ placed: TreeLayout.Placed) -> some View {
        let node = placed.node
        let isCurrent = node.id == currentID
        let isLive = node.id == liveID
        return ZStack {
            if let color = node.color {
                if node.pass {
                    Circle()
                        .strokeBorder(Theme.stone(color), style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 1.5]))
                        .frame(width: Self.stone, height: Self.stone)
                } else {
                    Circle()
                        .fill(Theme.stone(color))
                        .overlay(Circle().strokeBorder(Theme.stoneEdge(color).opacity(0.6), lineWidth: 0.5))
                        .frame(width: Self.stone, height: Self.stone)
                }
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.secondaryText)
                    .frame(width: 8, height: 8)
            }
            if isLive {
                Circle()
                    .strokeBorder(Theme.connected, lineWidth: 1.5)
                    .frame(width: Self.stone + 5, height: Self.stone + 5)
            }
            if isCurrent {
                Circle()
                    .strokeBorder(Theme.localMove, lineWidth: 2)
                    .frame(width: Self.stone + 7, height: Self.stone + 7)
            }
        }
        .opacity(node.origin == .preview ? 0.65 : 1)
        .frame(width: Self.columnWidth, height: Self.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(node.id) }
        .contextMenu {
            if canDelete(node.id) {
                Button("Supprimer la variante", role: .destructive) { onDelete(node.id) }
            }
        }
        .help(Self.describe(placed, isLive: isLive))
        .accessibilityElement()
        .accessibilityLabel(Self.describe(placed, isLive: isLive))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    static func describe(_ placed: TreeLayout.Placed, isLive: Bool) -> String {
        let node = placed.node
        guard let color = node.color else { return "Début de la partie" }
        var words = "Coup \(placed.row), \(Theme.name(color))"
        if node.pass { words += " passe" }
        switch node.origin {
        case .game: break
        case .record: words += ", variante du fichier"
        case .analysis: words += ", variante"
        case .preview: words += ", proposition"
        }
        if isLive { words += ", partie en cours" }
        return words
    }
}
