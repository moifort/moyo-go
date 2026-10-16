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
