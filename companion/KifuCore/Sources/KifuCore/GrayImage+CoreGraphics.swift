#if canImport(CoreGraphics)
import CoreGraphics

extension GrayImage {
    /// Converts any CGImage to 8-bit grayscale, optionally downscaled by an integer factor.
    public init?(cgImage: CGImage, downscale: Int = 1) {
        let width = cgImage.width / downscale, height = cgImage.height / downscale
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }
}
#endif
