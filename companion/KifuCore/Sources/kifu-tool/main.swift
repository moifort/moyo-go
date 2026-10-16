import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import KifuCore

// kifu-tool read <photo> --corners x,y,x,y,x,y,x,y [--lines 19] [--height 0] [--fit 15] [--overlay out.png]
//   Prints the (fitted) corners, the position read and per-intersection measures on demand,
//   and writes an overlay image showing the grid and the stones read.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
guard args.first == "read", args.count >= 2 else {
    fail("usage: kifu-tool read <photo> --corners x,y,x,y,x,y,x,y [--lines 19] [--height 0] [--fit 15] [--overlay out.png] [--measures]")
}
args.removeFirst()
let photo = URL(fileURLWithPath: args.removeFirst())
var corners: [Point] = []
var anchors: [(Point, Point)] = []
var lines = 19
var height = 0.0
var fitRadius = 0
var overlay: URL?
var printMeasures = false
while !args.isEmpty {
    let flag = args.removeFirst()
    switch flag {
    case "--corners":
        let v = args.removeFirst().split(separator: ",").compactMap { Double($0) }
        guard v.count == 8 else { fail("--corners needs 8 numbers") }
        corners = stride(from: 0, to: 8, by: 2).map { Point(x: v[$0], y: v[$0 + 1]) }
    case "--anchors":
        // Four known intersections "col,row,x,y;col,row,x,y;..." from which the corners are derived.
        let groups = args.removeFirst().split(separator: ";").map { $0.split(separator: ",").compactMap { Double($0) } }
        guard groups.count == 4, groups.allSatisfy({ $0.count == 4 }) else { fail("--anchors needs 4 groups of 4 numbers") }
        anchors = groups.map { (Point(x: $0[0], y: $0[1]), Point(x: $0[2], y: $0[3])) }
    case "--lines": lines = Int(args.removeFirst())!
    case "--height": height = Double(args.removeFirst())!
    case "--fit": fitRadius = Int(args.removeFirst())!
    case "--overlay": overlay = URL(fileURLWithPath: args.removeFirst())
    case "--measures": printMeasures = true
    default: fail("unknown flag \(flag)")
    }
}
if !anchors.isEmpty {
    guard let h = Homography(from: anchors.map(\.0), to: anchors.map(\.1)) else { fail("degenerate anchors") }
    let n = Double(lines - 1)
    corners = [Point(x: 0, y: 0), Point(x: n, y: 0), Point(x: n, y: n), Point(x: 0, y: n)].map(h.apply)
    print("corners from anchors: " + corners.map { String(format: "%.1f,%.1f", $0.x, $0.y) }.joined(separator: " "))
}
guard corners.count == 4 else { fail("--corners or --anchors is required") }

guard let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
      let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let image = GrayImage(cgImage: cg) else { fail("cannot read \(photo.path)") }
print("image \(image.width)x\(image.height)")

if fitRadius > 0 {
    corners = BoardGeometry.fitCorners(corners, lines: lines, in: image, radius: fitRadius)
    print("fitted corners: " + corners.map { String(format: "%.1f,%.1f", $0.x, $0.y) }.joined(separator: " "))
}
guard let geometry = BoardGeometry(calibration: Calibration(lines: lines, corners: corners)) else { fail("degenerate corners") }
print(String(format: "min spacing %.1f px, away from camera (%.0f, %.0f)", geometry.minSpacing, geometry.awayFromCamera.0, geometry.awayFromCamera.1))

var settings = ReaderSettings()
settings.stoneHeight = height
let reader = IntersectionReader(geometry: geometry, settings: settings)
let readings = reader.read(image, previous: nil)
print(readings.position)
if !readings.unreadable.isEmpty { print("unreadable: \(readings.unreadable.sorted())") }
if printMeasures {
    for i in readings.position.all {
        let m = reader.measure(image, at: i)
        print(String(format: "%@ stone %.0f wood %.0f ratio %.2f headroom %.2f dev %.0f", i.description, m.stone, m.wood, m.contrast, m.headroom, m.deviation))
    }
}

if let overlay {
    let w = cg.width, h = cg.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no context") }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    // CoreGraphics origin is bottom-left: flip y.
    func cgPoint(_ p: Point) -> CGPoint { CGPoint(x: p.x, y: Double(h) - p.y) }
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(CGColor(red: 1, green: 0.9, blue: 0, alpha: 0.9))
    let n = Double(lines - 1)
    for k in 0..<lines {
        let t = Double(k)
        ctx.move(to: cgPoint(geometry.imagePoint(boardX: t, boardY: 0)))
        ctx.addLine(to: cgPoint(geometry.imagePoint(boardX: t, boardY: n)))
        ctx.move(to: cgPoint(geometry.imagePoint(boardX: 0, boardY: t)))
        ctx.addLine(to: cgPoint(geometry.imagePoint(boardX: n, boardY: t)))
    }
    ctx.strokePath()
    let away = geometry.awayFromCamera
    for i in readings.position.all {
        let lift = reader.stoneLift(at: i)
        let c = geometry.imagePoint(boardX: Double(i.col) + away.0 * lift, boardY: Double(i.row) + away.1 * lift)
        let r = max(3.0, geometry.minSpacing * 0.25)
        let rect = CGRect(x: c.x - r, y: Double(h) - c.y - r, width: 2 * r, height: 2 * r)
        switch readings.position[i] {
        case .black: ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.strokeEllipse(in: rect)
        case .white: ctx.setStrokeColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1)); ctx.strokeEllipse(in: rect)
        case .empty: break
        }
    }
    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(overlay as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("cannot write overlay") }
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    print("overlay written to \(overlay.path)")
}
