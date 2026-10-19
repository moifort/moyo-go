import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import KifuCore

/// `kifu-tool eval cases.json [--only name] [--overlays dir]` reads every case with
/// the intersection reader and the scene reader, and counts each one's mistakes against the truth.
struct EvalCase: Decodable {
    let name: String
    let image: String
    let corners: [[Double]]
    let fit: Int?
    let expected: [String]
    let ignore: [[Int]]?
    let stoneHeight: Double?
}

func loadGray(_ path: String) -> (GrayImage, CGImage)? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
          let image = GrayImage(cgImage: cg) else { return nil }
    return (image, cg)
}

struct Score {
    var wrong = 0, unsure = 0, frames = 0, perfect = 0
    mutating func add(wrong w: Int, unsure u: Int) {
        wrong += w; unsure += u; frames += 1
        if w == 0 && u == 0 { perfect += 1 }
    }
    var line: String { "\(frames) images, \(perfect) parfaites, \(wrong) erreurs, \(unsure) incertaines" }
}

func writeOverlay(_ cg: CGImage, reader: SceneReader, reading: SceneReading, geometry: BoardGeometry, lens: Lens, to url: URL) {
    let (w, h, scale) = reader.reducedSize
    let labels = reader.labelMap()
    let W = cg.width, H = cg.height
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    ctx.setLineWidth(1)
    ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0, alpha: 0.8))
    for k in 0..<19 {
        let t = Double(k)
        for along in [true, false] {
            for s in 0...36 {
                let u = Double(s) / 2
                let p = lens.distort(along ? geometry.imagePoint(boardX: t, boardY: u) : geometry.imagePoint(boardX: u, boardY: t))
                if s == 0 { ctx.move(to: CGPoint(x: p.x, y: Double(H) - p.y)) } else { ctx.addLine(to: CGPoint(x: p.x, y: Double(H) - p.y)) }
            }
        }
    }
    ctx.strokePath()
    // Outline of every predicted stone region: a reduced pixel whose label differs from a neighbour's.
    for y in 1..<(h - 1) {
        for x in 1..<(w - 1) {
            let l = labels[y * w + x]
            guard l >= 2 else { continue }
            let edge = [labels[y * w + x - 1], labels[y * w + x + 1], labels[(y - 1) * w + x], labels[(y + 1) * w + x]].contains { $0 != l }
            guard edge else { continue }
            if l == 2 { ctx.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1)) } else { ctx.setFillColor(CGColor(red: 0, green: 0.6, blue: 1, alpha: 1)) }
            ctx.fill(CGRect(x: x * scale, y: H - (y + 1) * scale, width: scale, height: scale))
        }
    }
    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

func runEval(_ arguments: [String]) {
    var args = arguments
    let path = args.removeFirst()
    var only: String?
    var overlays: URL?
    var settings = SceneSettings()
    var skipOld = false
    var refine = false
    var probes: [Intersection] = []
    while !args.isEmpty {
        let flag = args.removeFirst()
        switch flag {
        case "--only": only = args.removeFirst()
        case "--overlays": overlays = URL(fileURLWithPath: args.removeFirst())
        case "--prior": settings.stonePrior = Double(args.removeFirst())!
        case "--radius": settings.stoneRadius = Double(args.removeFirst())!
        case "--thickness": settings.stoneHeight = Double(args.removeFirst())!
        case "--spacing": settings.targetSpacing = Double(args.removeFirst())!
        case "--offset": settings.offset = Double(args.removeFirst())!
        case "--probe": probes = args.removeFirst().split(separator: ";").map { $0.split(separator: ",").map { Int($0)! } }.map { Intersection(col: $0[0], row: $0[1]) }
        case "--cells": settings.woodCells = Int(args.removeFirst())!
        case "--area": settings.areaPrior = Double(args.removeFirst())!
        case "--jitter": settings.jitter = Double(args.removeFirst())!
        case "--shadow": let v = args.removeFirst().split(separator: ",").map { Double($0)! }; settings.shadowRatio = v[0]; settings.shadowCost = v[1]
        case "--clip": settings.clip = Double(args.removeFirst())!
        case "--unsure": settings.unsureBelow = Double(args.removeFirst())!
        case "--new-only": skipOld = true
        case "--refine": refine = true
        default: fail("unknown flag \(flag)")
        }
    }
    guard let data = FileManager.default.contents(atPath: path),
          let cases = try? JSONDecoder().decode([EvalCase].self, from: data) else { fail("cannot read \(path)") }
    var old = Score(), new = Score()
    var newTime = 0.0
    let selected = cases.filter { only == nil || $0.name.contains(only!) }
    var reports = [String](repeating: "", count: selected.count)
    var oldScores = [(Int, Int)?](repeating: nil, count: selected.count)
    var newScores = [(Int, Int, Double)?](repeating: nil, count: selected.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: selected.count) { index in
        let c = selected[index]
        func print(_ items: Any...) { let line = items.map { "\($0)" }.joined(separator: " "); lock.withLock { reports[index] += line + "\n" } }
        guard let (image, cg) = loadGray(c.image) else { print("\(c.name): unreadable image"); return }
        var corners = c.corners.map { Point(x: $0[0], y: $0[1]) }
        if let fit = c.fit, fit > 0 { corners = BoardGeometry.fitCorners(corners, lines: 19, in: image, radius: fit) }
        var k1 = 0.0
        var lensCorners = corners
        if refine {
            let before = SceneReader.score(corners, lens: Lens(width: image.width, height: image.height), lines: 19, in: image)
            let (fitted, lens) = SceneReader.fitGrid(corners, lines: 19, in: image)
            lensCorners = fitted; k1 = lens.k1
            if only != nil {
                print(String(format: "grid score %.2f -> %.2f, k1 %.4f ", before, SceneReader.score(fitted, lens: lens, lines: 19, in: image), k1) + fitted.map { String(format: "%.1f,%.1f", $0.x, $0.y) }.joined(separator: " "))
            }
        }
        let calibration = Calibration(lines: 19, corners: corners)
        let truth = Position(parsing: c.expected.joined(separator: "\n"))
        let ignored = Set((c.ignore ?? []).map { Intersection(col: $0[0], row: $0[1]) })

        var report = c.name
        if !skipOld, let geometry = BoardGeometry(calibration: calibration) {
            var rs = ReaderSettings()
            if let hgt = c.stoneHeight { rs.stoneHeight = hgt }
            let r = IntersectionReader(geometry: geometry, settings: rs).read(image, previous: nil)
            let wrong = truth.all.filter { !ignored.contains($0) && !r.unreadable.contains($0) && r.position[$0] != truth[$0] }
            let unsure = truth.all.filter { !ignored.contains($0) && r.unreadable.contains($0) && truth[$0] != .empty }
            lock.withLock { oldScores[index] = (wrong.count, unsure.count) }
            report += "  actuel: \(wrong.count) faux \(wrong.map(\.description).joined()) \(unsure.count) ? \(unsure.map(\.description).joined())"
        }
        let t = Date()
        guard let scene = SceneReader(image: image, calibration: Calibration(lines: 19, corners: lensCorners), k1: k1, settings: settings) else { print("\(c.name): no scene"); return }
        let built = -t.timeIntervalSinceNow
        let s = scene.read(previous: nil)
        if only != nil { print(String(format: "build %.2f s, read %.2f s ", built, -t.timeIntervalSinceNow - built) + scene.timings.map { "\($0.key) \(String(format: "%.2f", $0.value))" }.joined(separator: " ")) }
        let elapsed = -t.timeIntervalSinceNow
        let wrong = truth.all.filter { !ignored.contains($0) && s.position[$0] != truth[$0] }
        let unsure = truth.all.filter { !ignored.contains($0) && s.unsure.contains($0) && s.position[$0] == truth[$0] }
        lock.withLock { newScores[index] = (wrong.count, unsure.count, elapsed) }
        let detail = wrong.map { "\($0.description)\(s.position[$0] == .black ? "X" : s.position[$0] == .white ? "O" : ".")" }.joined()
        report += "  | rendu: \(wrong.count) faux \(detail) \(unsure.count) incertaines"
        print(report)
        for i in probes { print(scene.probe(i)) }
        if only != nil { print(String(format: "total cost %.0f", scene.totalCost)); print(scene.cameraReport); print(scene.appearance); print(s.position); print("incertaines: \(s.unsure.sorted().map { "\($0)\(String(format: "%.1f", s.margins[$0]!))" }.joined(separator: " "))") }
        if let overlays {
            try? FileManager.default.createDirectory(at: overlays, withIntermediateDirectories: true)
            writeOverlay(cg, reader: scene, reading: s, geometry: BoardGeometry(calibration: Calibration(lines: 19, corners: lensCorners))!, lens: Lens(k1: k1, width: image.width, height: image.height), to: overlays.appendingPathComponent(c.name.replacingOccurrences(of: "/", with: "_") + ".jpg"))
        }
    }
    for index in selected.indices {
        Swift.print(reports[index], terminator: "")
        if let o = oldScores[index] { old.add(wrong: o.0, unsure: o.1) }
        if let n = newScores[index] { new.add(wrong: n.0, unsure: n.1); newTime += n.2 }
    }
    if !skipOld { print("lecteur actuel : " + old.line) }
    print("lecteur par rendu : " + new.line + String(format: ", %.2f s par image", newTime / Double(max(new.frames, 1))))
}

/// `kifu-tool replay cases.json`: reads the cases in order with one scene reader per set of
/// corners, each image starting from the last reading, the way the app follows a game.
func runReplay(_ arguments: [String]) {
    guard let data = FileManager.default.contents(atPath: arguments[0]),
          let cases = try? JSONDecoder().decode([EvalCase].self, from: data) else { fail("cannot read \(arguments[0])") }
    var reader: SceneReader?
    var corners: [[Double]] = []
    var previous: Position?
    var score = Score()
    var times: [Double] = []
    for c in cases {
        guard let (image, _) = loadGray(c.image) else { continue }
        let t = Date()
        if reader == nil || c.corners != corners {
            reader = SceneReader(calibration: Calibration(lines: 19, corners: c.corners.map { Point(x: $0[0], y: $0[1]) }), imageWidth: image.width, imageHeight: image.height)
            corners = c.corners
        }
        let built = -t.timeIntervalSinceNow
        let r = reader!.read(image, previous: previous)
        let elapsed = -t.timeIntervalSinceNow
        times.append(elapsed - built)
        previous = r.position
        let truth = Position(parsing: c.expected.joined(separator: "\n"))
        let wrong = truth.all.filter { r.position[$0] != truth[$0] }
        let unsure = truth.all.filter { r.unreadable.contains($0) }
        score.add(wrong: wrong.count, unsure: unsure.count)
        print(String(format: "%@ build %.2f read %.2f  %d faux %@  %d incertaines %@", c.name, built, elapsed - built, wrong.count, wrong.map(\.description).joined(), unsure.count, unsure.map(\.description).joined()))
    }
    if let reader { print(reader.timings.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.2f", $0.value))" }.joined(separator: " ")) }
    print("relecture : " + score.line + String(format: ", lecture médiane %.2f s", times.sorted()[times.count / 2]))
}
