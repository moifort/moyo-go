import Foundation

/// The tree of variations laid out in columns, the way a git graph is drawn.
///
/// One row per move number, so a node's row is its move number and every branch
/// lines up with the move of the game it answers. The line of the game keeps the
/// first column; each branch takes the first column to its parent's right that is
/// free from the row before it starts to the row it ends, so two branches never
/// share a column over the same moves.
public struct TreeLayout: Sendable {
    public struct Placed: Sendable, Hashable, Identifiable {
        public let node: TreeNode
        /// The move number: 0 is the root, the empty board or its setup.
        public let row: Int
        public let column: Int

        public var id: Int { node.id }
    }

    /// A line from a node to one of its children, drawn straight down when they
    /// share a column, bent towards the child's column otherwise.
    public struct Edge: Sendable, Hashable {
        public let from: Slot
        public let to: Slot
        public let origin: TreeNode.Origin
    }

    public struct Slot: Sendable, Hashable {
        public let row: Int
        public let column: Int
    }

    public let placed: [Placed]
    public let edges: [Edge]
    public let rows: Int
    public let columns: Int

    private let slots: [Int: Slot]

    public init(nodes: [TreeNode]) {
        var children: [Int: [TreeNode]] = [:]
        var roots: [TreeNode] = []
        for node in nodes {
            if let parent = node.parent {
                children[parent, default: []].append(node)
            } else {
                roots.append(node)
            }
        }
        // The game's own move first: it carries on in its parent's column, whatever
        // order the branches were played in.
        for (parent, list) in children {
            children[parent] = list.filter { $0.origin == .game } + list.filter { $0.origin != .game }
        }

        var slots: [Int: Slot] = [:]
        var placed: [Placed] = []
        var edges: [Edge] = []
        /// Rows taken in each column, as closed ranges.
        var taken: [[ClosedRange<Int>]] = []

        func isFree(_ column: Int, _ span: ClosedRange<Int>) -> Bool {
            guard column < taken.count else { return true }
            return !taken[column].contains { $0.overlaps(span) }
        }

        func take(_ column: Int, _ span: ClosedRange<Int>) {
            while taken.count <= column { taken.append([]) }
            taken[column].append(span)
        }

        /// How deep the line that follows first children from `node` goes.
        func lineEnd(_ node: TreeNode, row: Int) -> Int {
            var node = node
            var row = row
            while let next = children[node.id]?.first {
                node = next
                row += 1
            }
            return row
        }

        /// Places a line — a node and its first children, all in one column — then
        /// every branch hanging from it, in order, depth first.
        func place(line start: TreeNode, row: Int, column: Int) {
            var node = start
            var row = row
            var line: [(TreeNode, Int)] = []
            while true {
                let slot = Slot(row: row, column: column)
                slots[node.id] = slot
                placed.append(Placed(node: node, row: row, column: column))
                line.append((node, row))
                guard let next = children[node.id]?.first else { break }
                edges.append(Edge(from: slot, to: Slot(row: row + 1, column: column), origin: next.origin))
                node = next
                row += 1
            }
            for (node, row) in line {
                for branch in (children[node.id] ?? []).dropFirst() {
                    let span = row...lineEnd(branch, row: row + 1)
                    var target = column + 1
                    while !isFree(target, span) { target += 1 }
                    take(target, span)
                    edges.append(
                        Edge(
                            from: Slot(row: row, column: column),
                            to: Slot(row: row + 1, column: target),
                            origin: branch.origin
                        )
                    )
                    place(line: branch, row: row + 1, column: target)
                }
            }
        }

        var column = 0
        for root in roots {
            let span = 0...lineEnd(root, row: 0)
            while !isFree(column, span) { column += 1 }
            take(column, span)
            place(line: root, row: 0, column: column)
        }

        self.slots = slots
        self.placed = placed.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        self.edges = edges
        self.rows = (placed.map(\.row).max() ?? -1) + 1
        self.columns = (placed.map(\.column).max() ?? -1) + 1
    }

    public func slot(of id: Int) -> Slot? { slots[id] }
}
