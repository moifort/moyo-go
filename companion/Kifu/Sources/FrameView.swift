import SwiftUI
import KifuCore

/// The camera frame scaled to fit, with an overlay built in the same coordinate frame.
struct FrameView<Overlay: View>: View {
    let preview: CGImage?
    let imageSize: CGSize
    @ViewBuilder var overlay: (CGRect) -> Overlay

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let preview {
                    Image(decorative: preview, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                overlay(CGRect(origin: .zero, size: geo.size))
            }
        }
    }
}

/// Magnified view of the frame around a point, shown above the finger while placing a corner.
struct Loupe: View {
    let preview: CGImage
    let imageSize: CGSize
    let frame: CGRect
    let point: CGPoint
    static let diameter: CGFloat = 120
    static let magnification: CGFloat = 3

    var body: some View {
        let shown = ImageMapping.displayedRect(imageSize: imageSize, in: frame)
        let big = CGSize(width: shown.width * Self.magnification, height: shown.height * Self.magnification)
        let dx = (point.x - shown.minX) * Self.magnification
        let dy = (point.y - shown.minY) * Self.magnification
        ZStack {
            Image(decorative: preview, scale: 1, orientation: .up)
                .resizable()
                .frame(width: big.width, height: big.height)
                .offset(x: Self.diameter / 2 - dx, y: Self.diameter / 2 - dy)
            Path { p in
                p.move(to: CGPoint(x: Self.diameter / 2 - 10, y: Self.diameter / 2))
                p.addLine(to: CGPoint(x: Self.diameter / 2 + 10, y: Self.diameter / 2))
                p.move(to: CGPoint(x: Self.diameter / 2, y: Self.diameter / 2 - 10))
                p.addLine(to: CGPoint(x: Self.diameter / 2, y: Self.diameter / 2 + 10))
            }
            .stroke(.orange, lineWidth: 1.5)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(radius: 4)
        .position(x: point.x, y: max(Self.diameter / 2 + 8, point.y - Self.diameter / 2 - 30))
        .allowsHitTesting(false)
    }
}
