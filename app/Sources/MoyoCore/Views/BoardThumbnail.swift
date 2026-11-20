import SwiftUI

/// A game's last position, small: the library's cards and its band.
///
/// Drawn like `BoardView` — the wood, the grid, the star points, the stones with
/// their fine edge — from the text the bridge wrote when it kept the game. No
/// coordinates, no marks, no engine: only the shape of the game.
struct BoardThumbnail: View {
    let board: LibraryEntry.Board

    var body: some View {
        Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            let size = max(2, board.size)
            let margin = BoardGeometry.woodMargin
            let step = side / (CGFloat(size - 1) + 2 * margin)
            let origin = CGPoint(
                x: (canvas.width - side) / 2 + margin * step,
                y: (canvas.height - side) / 2 + margin * step
            )
            func position(_ row: Int, _ col: Int) -> CGPoint {
                CGPoint(x: origin.x + CGFloat(col) * step, y: origin.y + CGFloat(row) * step)
            }

            let wood = CGRect(
                x: (canvas.width - side) / 2, y: (canvas.height - side) / 2, width: side, height: side
            )
            context.fill(
                Path(roundedRect: wood, cornerRadius: max(3, side * 0.03)),
                with: .color(Theme.wood)
            )

            var grid = Path()
            for index in 0..<size {
                grid.move(to: position(index, 0))
                grid.addLine(to: position(index, size - 1))
                grid.move(to: position(0, index))
                grid.addLine(to: position(size - 1, index))
            }
            context.stroke(grid, with: .color(Theme.gridLine), lineWidth: max(0.4, step * 0.8 / 28))

            let star = max(0.8, step * 3 / 28)
            for point in BoardGeometry(size: size, side: side).starPoints {
                let center = position(point.row, point.col)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - star, y: center.y - star, width: star * 2, height: star * 2)),
                    with: .color(Theme.gridLine)
                )
            }

            let radius = step * 13 / 28
            for row in 0..<size {
                for col in 0..<size {
                    guard let color = board.stone(row: row, col: col) else { continue }
                    let center = position(row, col)
                    let path = Path(
                        ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    )
                    context.fill(path, with: .color(Theme.stone(color)))
                    context.stroke(
                        path,
                        with: .color(Theme.stoneEdge(color)),
                        lineWidth: max(0.35, step * (color == .black ? 0.5 : 0.8) / 28)
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
