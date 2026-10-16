import Foundation

/// 8-bit grayscale image, origin top-left, rows top to bottom.
public struct GrayImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixels.count must equal width*height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt8 = 255) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: fill, count: width * height))
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    public mutating func set(x: Int, y: Int, value: UInt8) {
        pixels[y * width + x] = value
    }

    /// Bilinear sample at a sub-pixel position. Coordinates outside the image clamp to the border.
    public func sample(x: Double, y: Double) -> Double {
        let cx = min(max(x, 0), Double(width - 1))
        let cy = min(max(y, 0), Double(height - 1))
        let x0 = Int(cx), y0 = Int(cy)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = cx - Double(x0), fy = cy - Double(y0)
        let top = Double(self[x0, y0]) * (1 - fx) + Double(self[x1, y0]) * fx
        let bottom = Double(self[x0, y1]) * (1 - fx) + Double(self[x1, y1]) * fx
        return top * (1 - fy) + bottom * fy
    }
}
