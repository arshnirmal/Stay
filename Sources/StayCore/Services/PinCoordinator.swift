import Foundation
import CoreGraphics
import CoreMedia
import AppKit

private final class SampleBox: @unchecked Sendable {
    let buffer: CMSampleBuffer
    init(_ buffer: CMSampleBuffer) { self.buffer = buffer }
}

@MainActor
public final class PinCoordinator: ObservableObject {
    public static let shared = PinCoordinator()

    @Published public private(set) var activeSessions: [CGWindowID: PinSession] = [:]
    private var engines: [CGWindowID: CaptureEngine] = [:]

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    public func toggleActiveWindow() async throws {
        guard let target = WindowDiscoveryService.shared.getFrontmostTargetWindow() else {
            return
        }
        if activeSessions[target.id] != nil {
            await unpin(windowID: target.id)
        } else {
            try await pin(target: target)
        }
    }

    public func pin(target: TargetWindow) async throws {
        guard activeSessions[target.id] == nil else { return }
        let session = PinSession(target: target)

        let overlay = OverlayWindowManager.shared.createOverlay(for: target, configuration: session.configuration) {
            // Smart Focus click: bring target app forward
            if let app = NSRunningApplication(processIdentifier: target.pid) {
                app.activate()
            }
        }

        let engine = CaptureEngine(windowID: target.id) { [weak overlay] sampleBuffer in
            let box = SampleBox(sampleBuffer)
            Task { @MainActor in
                overlay?.renderFrame(box.buffer)
            }
        }

        try await engine.start()
        engines[target.id] = engine
        activeSessions[target.id] = session

        SmartFocusSyncService.shared.register(session: session, engine: engine, panel: overlay)
    }

    public func unpin(windowID: CGWindowID) async {
        if let engine = engines.removeValue(forKey: windowID) {
            await engine.stop()
        }
        OverlayWindowManager.shared.closeOverlay(for: windowID)
        SmartFocusSyncService.shared.unregister(windowID: windowID)
        activeSessions.removeValue(forKey: windowID)
    }

    public func unpinAll() async {
        let keys = Array(activeSessions.keys)
        for key in keys {
            await unpin(windowID: key)
        }
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        let deadPID = app.processIdentifier
        let toRemove = activeSessions.values.filter { $0.target.pid == deadPID }.map { $0.id }
        for wid in toRemove {
            Task { @MainActor in
                await self.unpin(windowID: wid)
            }
        }
    }
}
