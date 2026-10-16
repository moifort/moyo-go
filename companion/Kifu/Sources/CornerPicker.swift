import SwiftUI
import UIKit
import KifuCore

/// A full-resolution frame the user can pinch-zoom and pan, tapping to place a corner.
/// Content coordinates are frame pixels, so a tap gives the pixel directly.
struct CornerPicker: UIViewRepresentable {
    let image: CGImage
    let taps: [Point]
    let onTap: (Point) -> Void

    func makeUIView(context: Context) -> ZoomView {
        let view = ZoomView(image: image)
        view.onTap = onTap
        return view
    }

    func updateUIView(_ view: ZoomView, context: Context) {
        if view.image !== image { view.setImage(image) }
        view.onTap = onTap
        view.setMarkers(taps.map { CGPoint(x: $0.x, y: $0.y) })
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate {
        private(set) var image: CGImage
        private let content = UIView()
        private let imageView = UIImageView()
        private var markers: [MarkerView] = []
        var onTap: ((Point) -> Void)?
        private var fitted = false

        init(image: CGImage) {
            self.image = image
            super.init(frame: .zero)
            delegate = self
            showsVerticalScrollIndicator = false
            showsHorizontalScrollIndicator = false
            bouncesZoom = true
            maximumZoomScale = 2
            contentInsetAdjustmentBehavior = .never
            backgroundColor = .black
            addSubview(content)
            content.addSubview(imageView)
            imageView.contentMode = .scaleToFill
            setImage(image)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            content.addGestureRecognizer(tap)
        }

        required init?(coder: NSCoder) { fatalError() }

        func setImage(_ image: CGImage) {
            self.image = image
            let size = CGSize(width: image.width, height: image.height)
            content.frame = CGRect(origin: .zero, size: size)
            imageView.frame = content.bounds
            imageView.image = UIImage(cgImage: image)
            contentSize = size
            fitted = false
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0 else { return }
            let fit = min(bounds.width / content.bounds.width, bounds.height / content.bounds.height)
            minimumZoomScale = fit
            if !fitted {
                zoomScale = fit
                fitted = true
            }
            centerContent()
        }

        private func centerContent() {
            let w = content.frame.width, h = content.frame.height
            let dx = max(0, (bounds.width - w) / 2), dy = max(0, (bounds.height - h) / 2)
            contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent()
            for m in markers { m.transform = CGAffineTransform(scaleX: 1 / zoomScale, y: 1 / zoomScale) }
        }

        func setMarkers(_ points: [CGPoint]) {
            markers.forEach { $0.removeFromSuperview() }
            markers = points.enumerated().map { i, p in
                let m = MarkerView(number: i + 1)
                m.center = p
                m.transform = CGAffineTransform(scaleX: 1 / zoomScale, y: 1 / zoomScale)
                content.addSubview(m)
                return m
            }
        }

        @objc private func handleTap(_ g: UITapGestureRecognizer) {
            let p = g.location(in: content)
            guard content.bounds.contains(p) else { return }
            onTap?(Point(x: p.x, y: p.y))
        }
    }

    /// A ring with a crosshair and a number; drawn at screen size whatever the zoom.
    final class MarkerView: UIView {
        init(number: Int) {
            super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
            backgroundColor = .clear
            isUserInteractionEnabled = false
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 12, dy: 12)).cgPath
            ring.strokeColor = UIColor.systemOrange.cgColor
            ring.fillColor = UIColor.clear.cgColor
            ring.lineWidth = 2
            layer.addSublayer(ring)
            let cross = CAShapeLayer()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 22, y: 2)); path.addLine(to: CGPoint(x: 22, y: 14))
            path.move(to: CGPoint(x: 22, y: 30)); path.addLine(to: CGPoint(x: 22, y: 42))
            path.move(to: CGPoint(x: 2, y: 22)); path.addLine(to: CGPoint(x: 14, y: 22))
            path.move(to: CGPoint(x: 30, y: 22)); path.addLine(to: CGPoint(x: 42, y: 22))
            cross.path = path.cgPath
            cross.strokeColor = UIColor.systemOrange.cgColor
            cross.lineWidth = 1.5
            layer.addSublayer(cross)
            let label = UILabel(frame: CGRect(x: 28, y: -6, width: 20, height: 16))
            label.text = "\(number)"
            label.font = .boldSystemFont(ofSize: 13)
            label.textColor = .white
            label.shadowColor = .black
            label.shadowOffset = CGSize(width: 0, height: 1)
            addSubview(label)
        }

        required init?(coder: NSCoder) { fatalError() }
    }
}
