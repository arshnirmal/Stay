import Testing
import CoreGraphics
import AppKit
@testable import StayCore

@Suite("OverlayWindowManager Tests")
@MainActor
struct OverlayWindowManagerTests {
    @Test("OverlayPanel creation and floating level attributes")
    func testOverlayPanelAttributes() {
        let manager = OverlayWindowManager.shared
        let target = TargetWindow(
            id: 303,
            pid: 700,
            title: "Code",
            bundleID: "com.microsoft.VSCode",
            bounds: CGRect(x: 50, y: 50, width: 600, height: 400),
            role: "AXWindow"
        )
        let panel = manager.createOverlay(for: target, onClick: {})
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        manager.closeOverlay(for: 303)
    }
}
