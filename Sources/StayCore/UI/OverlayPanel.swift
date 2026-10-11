import AppKit
import AVFoundation

public final class OverlayPanel: NSPanel {
    public let displayLayer = AVSampleBufferDisplayLayer()
    private var onClick: (() -> Void)?

    public init(frame: NSRect, onClick: (() -> Void)? = nil) {
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
}
