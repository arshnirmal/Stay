import AppKit
import Foundation

@MainActor
public final class SmartFocusSyncService {
    public static let shared = SmartFocusSyncService()

    private struct Entry {
        let session: PinSession
        let engine: CaptureEngine
        let panel: OverlayPanel
    }

    private var registry: [CGWindowID: Entry] = [:]

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    public func register(session: PinSession, engine: CaptureEngine, panel: OverlayPanel) {
        registry[session.id] = Entry(session: session, engine: engine, panel: panel)
    }

    public func unregister(windowID: CGWindowID) {
        registry.removeValue(forKey: windowID)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        handleAppActivation(pid: app.processIdentifier)
    }

    public func handleAppActivation(pid: pid_t) {
        for (_, entry) in registry {
            if entry.session.target.pid == pid {
                // Target is frontmost: pause stream and hide overlay
                entry.engine.pause()
                entry.panel.orderOut(nil)
            } else {
                // Background app frontmost: resume stream and show overlay
                entry.engine.resume()
                entry.panel.orderFront(nil)
            }
        }
    }
}
