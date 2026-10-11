import AppKit
import AVFoundation
import CoreMedia

@MainActor
public final class OverlayWindowManager {
    public static let shared = OverlayWindowManager()
    private var panels: [CGWindowID: OverlayPanel] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    public static func calculateFrame(
        for target: TargetWindow,
        configuration: PeekerConfiguration,
        screenFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        switch configuration.mode {
        case .inPlace:
            return NSRect(
                x: target.bounds.origin.x,
                y: screenFrame.height - target.bounds.origin.y - target.bounds.height,
                width: target.bounds.width,
                height: target.bounds.height
            )

        case .corner(let corner):
            let targetAspect = max(0.1, target.bounds.width / max(1.0, target.bounds.height))
            let width = visibleFrame.width * configuration.scaleRatio
            let height = width / targetAspect
            let margin: CGFloat = 16

            let origin: NSPoint
            switch corner {
            case .bottomRight:
                origin = NSPoint(x: visibleFrame.maxX - width - margin, y: visibleFrame.minY + margin)
            case .bottomLeft:
                origin = NSPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin)
            case .topRight:
                origin = NSPoint(x: visibleFrame.maxX - width - margin, y: visibleFrame.maxY - height - margin)
            case .topLeft:
                origin = NSPoint(x: visibleFrame.minX + margin, y: visibleFrame.maxY - height - margin)
            }

            return NSRect(origin: origin, size: NSSize(width: width, height: height))
        }
    }

    public func createOverlay(
        for target: TargetWindow,
        configuration: PeekerConfiguration = PeekerConfiguration(),
        onClick: @escaping () -> Void
    ) -> OverlayPanel {
        let screen = NSScreen.screens.first ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = screen?.visibleFrame ?? screenFrame

        let frame = Self.calculateFrame(
            for: target,
            configuration: configuration,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        let panel = OverlayPanel(frame: frame, target: target, configuration: configuration, onClick: onClick)
        panel.orderFront(nil)
        panels[target.id] = panel
        return panel
    }

    public func updateConfiguration(_ config: PeekerConfiguration, for windowID: CGWindowID) {
        guard let panel = panels[windowID], let target = panel.target else { return }
        let screen = panel.screen ?? NSScreen.screens.first ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = screen?.visibleFrame ?? screenFrame

        let targetFrame = Self.calculateFrame(
            for: target,
            configuration: config,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        panel.applyConfiguration(config, targetFrame: targetFrame, animated: true)
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

    @objc private func screenParametersChanged() {
        for (_, panel) in panels {
            guard let target = panel.target else { continue }
            let screen = panel.screen ?? NSScreen.screens.first ?? NSScreen.main
            let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            let visibleFrame = screen?.visibleFrame ?? screenFrame
            let targetFrame = Self.calculateFrame(
                for: target,
                configuration: panel.configuration,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            )
            panel.applyConfiguration(panel.configuration, targetFrame: targetFrame, animated: false)
        }
    }
}
