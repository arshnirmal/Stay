import Testing
import CoreGraphics
import AppKit
@testable import StayCore

@Suite("SmartFocusSyncService Tests")
@MainActor
struct SmartFocusSyncServiceTests {
    @Test("App activation matching target triggers pause state")
    func testTargetActivationPause() {
        let sync = SmartFocusSyncService.shared
        let target = TargetWindow(
            id: 404,
            pid: 888,
            title: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            bounds: CGRect(x: 0, y: 0, width: 400, height: 400),
            role: "AXWindow"
        )
        let session = PinSession(target: target)
        let panel = OverlayPanel(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let engine = CaptureEngine(windowID: 404) { _ in }

        sync.register(session: session, engine: engine, panel: panel)
        sync.handleAppActivation(pid: 888)
        #expect(!panel.isVisible)

        sync.handleAppActivation(pid: 999)
        #expect(panel.isVisible)

        sync.unregister(windowID: 404)
        panel.close()
    }
}
