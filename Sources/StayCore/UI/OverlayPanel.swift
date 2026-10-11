import AppKit
import AVFoundation
import CoreMedia

public final class OverlayPanel: NSPanel {
    public let target: TargetWindow?
    public private(set) var configuration: PeekerConfiguration
    public let displayLayer = AVSampleBufferDisplayLayer()
    private var onClick: (() -> Void)?

    public init(
        frame: NSRect,
        target: TargetWindow? = nil,
        configuration: PeekerConfiguration = PeekerConfiguration(),
        onClick: (() -> Void)? = nil
    ) {
        self.target = target
        self.configuration = configuration
        self.onClick = onClick
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.alphaValue = configuration.opacity

        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1.5
        root.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor

        displayLayer.frame = root.bounds
        displayLayer.videoGravity = .resizeAspectFill
        root.layer?.addSublayer(displayLayer)
        self.contentView = root
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onClick?()
    }

    public func updateFrame(_ newFrame: NSRect) {
        self.setFrame(newFrame, display: true)
        if let root = self.contentView {
            displayLayer.frame = root.bounds
        }
    }

    public func applyConfiguration(_ newConfig: PeekerConfiguration, targetFrame: NSRect, animated: Bool) {
        self.configuration = newConfig
        self.alphaValue = newConfig.opacity

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(targetFrame, display: true)
            }
        } else {
            self.setFrame(targetFrame, display: true)
        }

        if let root = self.contentView {
            displayLayer.frame = root.bounds
        }
    }

    public func renderFrame(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }
}
