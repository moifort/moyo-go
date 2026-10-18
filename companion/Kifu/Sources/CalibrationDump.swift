import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import KifuCore

/// Saves each calibration attempt (full-resolution frame, taps, result) under Documents/Calibrage,
/// so that a bad detection can be replayed on a Mac with kifu-tool. Keeps the last few.
enum CalibrationDump {
    static let keep = 5

    static var directory: URL {
        GameSession.documents.appendingPathComponent("Calibrage", isDirectory: true)
    }

    static func save(frame: GrayImage, taps: [Point], corners: [Point]?) {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = f.string(from: Date())
        if let cg = cgImage(of: frame),
           let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, nil)
            CGImageDestinationFinalize(dest)
        }
        let info: [String: Any] = [
            "taps": taps.map { [$0.x, $0.y] },
            "corners": corners.map { $0.map { [$0.x, $0.y] } } ?? "not found",
            "width": frame.width, "height": frame.height,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted]) {
            try? data.write(to: dir.appendingPathComponent("\(name).json"))
        }
        prune(dir)
    }

    static func cgImage(of image: GrayImage) -> CGImage? {
        let data = Data(image.pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func prune(_ dir: URL) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.removeItem(at: old.deletingPathExtension().appendingPathExtension("json"))
        }
    }
}
