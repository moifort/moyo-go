import SwiftUI
import KifuCore

/// Frame pixels (origin top-left) <-> points of a view showing the frame `scaledToFit`.
enum ImageMapping {
    static func displayedRect(imageSize: CGSize, in frame: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }
        let scale = min(frame.width / imageSize.width, frame.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h)
    }

    static func toView(_ p: Point, imageSize: CGSize, in frame: CGRect) -> CGPoint {
        let r = displayedRect(imageSize: imageSize, in: frame)
        let s = r.width / imageSize.width
        return CGPoint(x: r.minX + p.x * s, y: r.minY + p.y * s)
    }

    static func toImage(_ p: CGPoint, imageSize: CGSize, in frame: CGRect) -> Point {
        let r = displayedRect(imageSize: imageSize, in: frame)
        let s = imageSize.width / r.width
        return Point(x: (p.x - r.minX) * s, y: (p.y - r.minY) * s)
    }
}
