import AppKit
import AVFoundation
import CoreMedia

@MainActor
public final class OverlayWindowManager {
    public static let shared = OverlayWindowManager()
    private var panels: [CGWindowID: OverlayPanel] = [:]

    private init() {}

    public func createOverlay(for target: TargetWindow, onClick: @escaping () -> Void) -> OverlayPanel {
        let primaryScreenHeight = (NSScreen.screens.first ?? NSScreen.main)?.frame.height ?? 1080
        let frame = NSRect(
            x: target.bounds.origin.x,
            y: primaryScreenHeight - target.bounds.origin.y - target.bounds.height,
            width: target.bounds.width,
            height: target.bounds.height
        )
        let panel = OverlayPanel(frame: frame, onClick: onClick)
        panel.orderFront(nil)
        panels[target.id] = panel
        return panel
    }

    public func renderFrame(_ sampleBuffer: CMSampleBuffer, in panel: OverlayPanel) {
        if panel.displayLayer.status == .failed {
            panel.displayLayer.flush()
        }
        panel.displayLayer.enqueue(sampleBuffer)
    }

    public func closeOverlay(for windowID: CGWindowID) {
        if let panel = panels.removeValue(forKey: windowID) {
            panel.orderOut(nil)
            panel.close()
        }
    }

    public func getOverlay(for windowID: CGWindowID) -> OverlayPanel? {
        panels[windowID]
    }
}
