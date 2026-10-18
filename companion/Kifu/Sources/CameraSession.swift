import AVFoundation
import CoreImage
import CoreVideo
import KifuCore

/// A camera frame: full-resolution luminance for the reader, a small colour image for the screen.
struct CameraFrame {
    let gray: GrayImage
    let preview: CGImage
    let time: TimeInterval
    /// Full-resolution colour image, only on the frame following `requestFullFrame()`.
    let full: CGImage?
}

/// Back camera (wide, or ultra wide when `useUltraWide` is set), largest 4:3 format, 2 frames
/// per second, frames rotated upright for the current interface orientation until
/// `lockForGame()` is called.
final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let frameRate: Int32 = 2
    static let previewDownscale = 4
    /// UserDefaults key: prefer the 13 mm ultra wide lens, as the printed stand expects
    /// (hardware/stand). Falls back to the wide lens on phones without one.
    static let ultraWideDefaultsKey = "ultraWideLens"
    static var useUltraWide: Bool { UserDefaults.standard.bool(forKey: ultraWideDefaultsKey) }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "Kifu.camera")
    private let output = AVCaptureVideoDataOutput()
    private let context = CIContext()
    private let onFrame: (CameraFrame) -> Void
    private var device: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var rotationLocked = false
    private var fullFrameRequested = false

    init(onFrame: @escaping (CameraFrame) -> Void) {
        self.onFrame = onFrame
    }

    /// False when the camera is refused or absent.
    func start() async -> Bool {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        let ultraWide = Self.useUltraWide
            ? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) : nil
        guard granted,
              let device = ultraWide ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        self.device = device

        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        guard session.canAddInput(input) else { session.commitConfiguration(); return false }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { session.commitConfiguration(); return false }
        session.addOutput(output)
        do {
            try device.lockForConfiguration()
            if let format = Self.bestFormat(for: device) { device.activeFormat = format }
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Self.frameRate)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Self.frameRate)
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            device.unlockForConfiguration()
        } catch {
            session.commitConfiguration()
            return false
        }
        session.commitConfiguration()

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] c, _ in
            self?.applyRotation(c.videoRotationAngleForHorizonLevelCapture)
        }
        queue.async { self.session.startRunning() }
        return true
    }

    /// The next frame will carry a full-resolution colour image.
    func requestFullFrame() {
        queue.async { self.fullFrameRequested = true }
    }

    func stop() {
        rotationObservation = nil
        queue.async { self.session.stopRunning() }
    }

    /// Freezes the frame orientation and the focus: the board does not move once calibrated.
    func lockForGame() {
        rotationLocked = true
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
        if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
        device.unlockForConfiguration()
    }

    func unlockForCalibration() {
        rotationLocked = false
        if let c = rotationCoordinator { applyRotation(c.videoRotationAngleForHorizonLevelCapture) }
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        device.unlockForConfiguration()
    }

    private func applyRotation(_ angle: CGFloat) {
        guard !rotationLocked, let connection = output.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// Largest 4:3 format that supports the frame rate.
    static func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats
            .filter { f in
                let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                let fourThree = d.width * 3 == d.height * 4
                let rate = f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= Double(frameRate) && $0.maxFrameRate >= Double(frameRate) }
                let yuv = CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                return fourThree && rate && yuv && !f.isVideoBinned
            }
            .max { a, b in
                CMVideoFormatDescriptionGetDimensions(a.formatDescription).width
                    < CMVideoFormatDescriptionGetDimensions(b.formatDescription).width
            }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let gray = Self.luminance(of: buffer) else { return }
        let ci = CIImage(cvPixelBuffer: buffer)
        let scale = 1.0 / CGFloat(Self.previewDownscale)
        let small = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let preview = context.createCGImage(small, from: small.extent) else { return }
        var full: CGImage?
        if fullFrameRequested {
            full = context.createCGImage(ci, from: ci.extent)
            fullFrameRequested = false
        }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        onFrame(CameraFrame(gray: gray, preview: preview, time: time, full: full))
    }

    /// Copies the Y plane of a 4:2:0 buffer: luminance for free, no colour conversion.
    static func luminance(of buffer: CVPixelBuffer) -> GrayImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) >= 1, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { dst in
            for y in 0..<height {
                memcpy(dst.baseAddress! + y * width, base + y * stride, width)
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }
}
