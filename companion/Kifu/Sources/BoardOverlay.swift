import SwiftUI
import KifuCore

/// Grid, stones and markers drawn over the camera frame.
struct BoardOverlay: View {
    let imageSize: CGSize
    let gridPoints: [[Point]]
    var stones: Position?
    var ghosts: Position?            // candidate stones not yet in the record, drawn hollow
    var lastMove: Intersection?
    var highlighted: Set<Intersection> = []
    var taps: [Point] = []

    var body: some View {
        Canvas { ctx, size in
            let frame = CGRect(origin: .zero, size: size)
            guard imageSize.width > 0 else { return }
            func v(_ p: Point) -> CGPoint { ImageMapping.toView(p, imageSize: imageSize, in: frame) }

            for (i, t) in taps.enumerated() {
                let c = v(t)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.orange))
                ctx.draw(Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white), at: CGPoint(x: c.x + 12, y: c.y - 12))
            }

            let n = gridPoints.count
            guard n > 1 else { return }
            var grid = Path()
            for i in 0..<n {
                grid.move(to: v(gridPoints[i][0])); grid.addLine(to: v(gridPoints[i][n - 1]))
                grid.move(to: v(gridPoints[0][i])); grid.addLine(to: v(gridPoints[n - 1][i]))
            }
            ctx.stroke(grid, with: .color(.yellow.opacity(0.7)), lineWidth: 0.8)

            let scale = ImageMapping.displayedRect(imageSize: imageSize, in: frame).width / imageSize.width
            func radius(at row: Int, col: Int) -> CGFloat {
                let here = gridPoints[row][col]
                let next = col + 1 < n ? gridPoints[row][col + 1] : gridPoints[row][col - 1]
                return max(3, CGFloat(abs(next.x - here.x)) * scale * 0.4)
            }
            for row in 0..<n {
                for col in 0..<n {
                    let i = Intersection(col: col, row: row)
                    let stone = stones?[i] ?? .empty
                    let ghost = ghosts?[i] ?? .empty
                    let c = v(gridPoints[row][col])
                    let r = radius(at: row, col: col)
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                    if stone != .empty {
                        ctx.fill(Path(ellipseIn: rect), with: .color(stone == .black ? .black : .white))
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.red.opacity(0.9)), lineWidth: 1.5)
                    } else if ghost != .empty {
                        ctx.stroke(Path(ellipseIn: rect), with: .color(ghost == .black ? .black : .white), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    }
                    if highlighted.contains(i) {
                        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(.orange), lineWidth: 3)
                    }
                    if lastMove == i {
                        let m = CGRect(x: c.x - r / 2, y: c.y - r / 2, width: r, height: r)
                        ctx.fill(Path(ellipseIn: m), with: .color(.red))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
