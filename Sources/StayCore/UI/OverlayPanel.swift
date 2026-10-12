import AppKit
import AVFoundation
import CoreMedia
import SwiftUI

public final class OverlayPanel: NSPanel {
    public let target: TargetWindow?
    public private(set) var configuration: PeekerConfiguration
    public let displayLayer = AVSampleBufferDisplayLayer()
    private var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var toolbarHost: NSHostingView<AnyView>?

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

        setupContentView(frame: frame)
        setupTrackingArea()
    }

    private func setupContentView(frame: NSRect) {
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1.5
        root.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor

        displayLayer.frame = root.bounds
        displayLayer.videoGravity = .resizeAspectFill
        root.layer?.addSublayer(displayLayer)

        let toolbarBinding = Binding<PeekerConfiguration>(
            get: { [weak self] in self?.configuration ?? PeekerConfiguration() },
            set: { [weak self] newConfig in
                guard let self else { return }
                self.configuration = newConfig
                self.alphaValue = newConfig.opacity
            }
        )

        let toolbarView = PeekerToolbarView(
            configuration: toolbarBinding,
            onToggleMode: { [weak self] in
                guard let self, let target = self.target else { return }
                var nextConfig = self.configuration
                switch nextConfig.mode {
                case .corner: nextConfig.mode = .inPlace
                case .inPlace: nextConfig.mode = .corner(.bottomRight)
                }
                OverlayWindowManager.shared.updateConfiguration(nextConfig, for: target.id)
            },
            onCycleCorner: { [weak self] in
                guard let self, let target = self.target else { return }
                var nextConfig = self.configuration
                if case .corner(let corner) = nextConfig.mode {
                    nextConfig.mode = .corner(corner.next)
                    OverlayWindowManager.shared.updateConfiguration(nextConfig, for: target.id)
                }
            },
            onUnpin: { [weak self] in
                guard let self, let target = self.target else { return }
                Task { @MainActor in
                    await PinCoordinator.shared.unpin(windowID: target.id)
                }
            }
        )

        let host = NSHostingView(rootView: AnyView(toolbarView))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.alphaValue = 0 // Hidden until hover
        root.addSubview(host)

        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            host.centerXAnchor.constraint(equalTo: root.centerXAnchor)
        ])

        self.toolbarHost = host
        self.contentView = root
    }

    private func setupTrackingArea() {
        guard let view = self.contentView else { return }
        if let existing = trackingArea { view.removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        self.trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            toolbarHost?.animator().alphaValue = 1.0
        }
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            toolbarHost?.animator().alphaValue = 0.0
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        if let host = toolbarHost, host.frame.contains(locationInWindow) {
            // Event handled by toolbar buttons
            return
        }
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
