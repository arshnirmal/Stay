import Foundation
import ScreenCaptureKit
import CoreMedia

public final class CaptureEngine: NSObject, SCStreamOutput, @unchecked Sendable {
    public let windowID: CGWindowID
    private var stream: SCStream?
    private let onFrame: @Sendable (CMSampleBuffer) -> Void
    private let streamQueue = DispatchQueue(label: "com.stay.capture.output", qos: .userInteractive)
    private let lock = NSLock()
    private var _running = false
    private var _paused = false

    public var isRunning: Bool {
        lock.withLock { _running }
    }

    public var isPaused: Bool {
        lock.withLock { _paused }
    }

    public init(windowID: CGWindowID, onFrame: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.windowID = windowID
        self.onFrame = onFrame
        super.init()
    }

    public func start() async throws {
        let isAlreadyRunning = lock.withLock { _running }
        guard !isAlreadyRunning else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let targetWindow = content.windows.first(where: { $0.windowID == self.windowID }) else {
            throw NSError(domain: "StayCaptureError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Window \(windowID) not found in SCShareableContent"])
        }

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 1
        config.capturesAudio = false
        config.showsCursor = true

        let fps = PowerManager.shared.currentState.targetFPS
        config.minimumFrameInterval = PowerManager.shared.frameInterval(for: fps)

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: streamQueue)
        try await newStream.startCapture()

        lock.withLock {
            self.stream = newStream
            self._running = true
            self._paused = false
        }
    }

    public func pause() {
        lock.withLock {
            guard _running && !_paused else { return }
            _paused = true
        }
    }

    public func resume() {
        lock.withLock {
            guard _running && _paused else { return }
            _paused = false
        }
    }

    public func stop() async {
        let streamToStop = lock.withLock { () -> SCStream? in
            guard _running else { return nil }
            let s = self.stream
            self.stream = nil
            self._running = false
            self._paused = false
            return s
        }
        try? await streamToStop?.stopCapture()
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let shouldDeliver = lock.withLock { !_paused }
        if shouldDeliver {
            onFrame(sampleBuffer)
        }
    }
}
