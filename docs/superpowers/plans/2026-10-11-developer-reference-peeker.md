# Developer Reference Peeker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Stay into a Developer Reference Peeker supporting dual display modes (Corner Thumbnail and 1:1 In-Place HUD), a hover glass toolbar with opacity controls, corner cycling, and hotkey shortcuts.

**Architecture:** AppKit floating `NSPanel` hosting an `AVSampleBufferDisplayLayer` video surface and an embedded SwiftUI glassmorphic hover toolbar (`PeekerToolbarView`). Layout engine computes aspect-ratio preserved frames anchored to `screen.visibleFrame`. Global hotkeys (`⌥⇧P`, `⌥⇧T`, `⌥⇧C`) route through `HotkeyService` to `PinCoordinator`.

**Tech Stack:** Swift 6, AppKit, ScreenCaptureKit, SwiftUI, Carbon Hotkeys, Swift Testing (`Testing`).

**Spec:** `docs/superpowers/specs/2026-10-11-developer-reference-peeker-design.md`

## Global Constraints

- macOS 14.0+ deployment target.
- Swift 6 strict concurrency (`@MainActor` and `Sendable` conformance).
- No third-party package dependencies; use native Apple frameworks.
- Do not trigger Smart Focus (`app.activate()`) when interacting with toolbar controls.
- Maintain power-aware throttling via `PowerManager`.

---

### Task 1: Core Peeker Configuration & Models

**Files:**
- Create: `Sources/StayCore/Models/PeekerConfiguration.swift`
- Modify: `Sources/StayCore/Models/PinSession.swift`
- Test: `Tests/StayTests/PeekerConfigurationTests.swift`

**Interfaces:**
- Consumes: None
- Produces: `CornerPosition`, `PeekerDisplayMode`, `PeekerConfiguration`, `PinSession.configuration`

- [ ] **Step 1: Write the failing unit tests for `PeekerConfiguration`**

Create `Tests/StayTests/PeekerConfigurationTests.swift`:
```swift
import Testing
import Foundation
@testable import StayCore

@Suite("Peeker Configuration Tests")
struct PeekerConfigurationTests {
    @Test("Default configuration values")
    func testDefaultValues() {
        let config = PeekerConfiguration()
        #expect(config.mode == .corner(.bottomRight))
        #expect(config.opacity == 0.90)
        #expect(config.scaleRatio == 0.30)
    }

    @Test("Opacity clamping between 0.20 and 1.0")
    func testOpacityClamping() {
        let low = PeekerConfiguration(opacity: 0.05)
        #expect(low.opacity == 0.20)

        let high = PeekerConfiguration(opacity: 1.5)
        #expect(high.opacity == 1.0)
    }

    @Test("Scale ratio clamping between 0.20 and 0.45")
    func testScaleRatioClamping() {
        let small = PeekerConfiguration(scaleRatio: 0.10)
        #expect(small.scaleRatio == 0.20)

        let large = PeekerConfiguration(scaleRatio: 0.80)
        #expect(large.scaleRatio == 0.45)
    }

    @Test("Corner cycling sequence")
    func testCornerCycling() {
        #expect(CornerPosition.bottomRight.next == .bottomLeft)
        #expect(CornerPosition.bottomLeft.next == .topLeft)
        #expect(CornerPosition.topLeft.next == .topRight)
        #expect(CornerPosition.topRight.next == .bottomRight)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PeekerConfigurationTests`
Expected: FAIL with "cannot find type 'PeekerConfiguration' in scope"

- [ ] **Step 3: Implement `PeekerConfiguration` and update `PinSession`**

Create `Sources/StayCore/Models/PeekerConfiguration.swift`:
```swift
import Foundation
import CoreGraphics

public enum CornerPosition: String, CaseIterable, Sendable, Codable {
    case bottomRight
    case bottomLeft
    case topLeft
    case topRight

    public var next: CornerPosition {
        switch self {
        case .bottomRight: return .bottomLeft
        case .bottomLeft:  return .topLeft
        case .topLeft:     return .topRight
        case .topRight:    return .bottomRight
        }
    }
}

public enum PeekerDisplayMode: Equatable, Sendable {
    case inPlace
    case corner(CornerPosition)
}

public struct PeekerConfiguration: Equatable, Sendable {
    public var mode: PeekerDisplayMode
    public var opacity: CGFloat
    public var scaleRatio: CGFloat

    public init(
        mode: PeekerDisplayMode = .corner(.bottomRight),
        opacity: CGFloat = 0.90,
        scaleRatio: CGFloat = 0.30
    ) {
        self.mode = mode
        self.opacity = max(0.20, min(1.0, opacity))
        self.scaleRatio = max(0.20, min(0.45, scaleRatio))
    }
}
```

Update `Sources/StayCore/Models/PinSession.swift`:
```swift
import Foundation
import CoreGraphics

public final class PinSession: Identifiable, ObservableObject, @unchecked Sendable {
    public let id: CGWindowID
    public let target: TargetWindow
    public let pinnedAt: Date
    @Published public var configuration: PeekerConfiguration

    public init(target: TargetWindow, configuration: PeekerConfiguration = PeekerConfiguration()) {
        self.id = target.id
        self.target = target
        self.pinnedAt = Date()
        self.configuration = configuration
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PeekerConfigurationTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/Models/PeekerConfiguration.swift Sources/StayCore/Models/PinSession.swift Tests/StayTests/PeekerConfigurationTests.swift
git commit -m "feat(models): add PeekerConfiguration, CornerPosition and update PinSession"
```

---

### Task 2: Safe-Area Peeker Layout Engine

**Files:**
- Modify: `Sources/StayCore/Services/OverlayWindowManager.swift`
- Test: `Tests/StayTests/PeekerLayoutTests.swift`

**Interfaces:**
- Consumes: `PeekerConfiguration`, `TargetWindow`
- Produces: `OverlayWindowManager.calculateFrame(for:configuration:screen:) -> NSRect`

- [ ] **Step 1: Write the failing unit tests for layout calculation**

Create `Tests/StayTests/PeekerLayoutTests.swift`:
```swift
import Testing
import AppKit
@testable import StayCore

@Suite("Peeker Layout Calculation Tests")
@MainActor
struct PeekerLayoutTests {
    let mockTarget = TargetWindow(
        id: 101,
        pid: 501,
        title: "Terminal",
        bundleID: "com.apple.Terminal",
        bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
        role: "AXWindow"
    )

    let mockScreenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let mockVisibleFrame = NSRect(x: 0, y: 30, width: 1920, height: 1025)

    @Test("In-place frame calculation converts to Cocoa coordinate origin")
    func testInPlaceFrameCalculation() {
        let frame = OverlayWindowManager.calculateFrame(
            for: mockTarget,
            configuration: PeekerConfiguration(mode: .inPlace),
            screenFrame: mockScreenFrame,
            visibleFrame: mockVisibleFrame
        )
        #expect(frame.origin.x == 100)
        // 1080 - 100 (top) - 600 (height) = 380
        #expect(frame.origin.y == 380)
        #expect(frame.size.width == 800)
        #expect(frame.size.height == 600)
    }

    @Test("Corner thumbnail calculation preserves aspect ratio and 16pt margin")
    func testCornerThumbnailBottomRight() {
        let config = PeekerConfiguration(mode: .corner(.bottomRight), scaleRatio: 0.30)
        let frame = OverlayWindowManager.calculateFrame(
            for: mockTarget,
            configuration: config,
            screenFrame: mockScreenFrame,
            visibleFrame: mockVisibleFrame
        )

        let expectedWidth: CGFloat = 1920 * 0.30 // 576
        let expectedHeight: CGFloat = 576 / (800.0 / 600.0) // 432
        let expectedX: CGFloat = mockVisibleFrame.maxX - expectedWidth - 16
        let expectedY: CGFloat = mockVisibleFrame.minY + 16

        #expect(frame.size.width == expectedWidth)
        #expect(frame.size.height == expectedHeight)
        #expect(frame.origin.x == expectedX)
        #expect(frame.origin.y == expectedY)
    }

    @Test("Corner thumbnail calculation for TopLeft")
    func testCornerThumbnailTopLeft() {
        let config = PeekerConfiguration(mode: .corner(.topLeft), scaleRatio: 0.30)
        let frame = OverlayWindowManager.calculateFrame(
            for: mockTarget,
            configuration: config,
            screenFrame: mockScreenFrame,
            visibleFrame: mockVisibleFrame
        )

        let expectedWidth: CGFloat = 1920 * 0.30
        let expectedHeight: CGFloat = expectedWidth / (800.0 / 600.0)
        let expectedX: CGFloat = mockVisibleFrame.minX + 16
        let expectedY: CGFloat = mockVisibleFrame.maxY - expectedHeight - 16

        #expect(frame.origin.x == expectedX)
        #expect(frame.origin.y == expectedY)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PeekerLayoutTests`
Expected: FAIL with "type 'OverlayWindowManager' has no member 'calculateFrame'"

- [ ] **Step 3: Implement `calculateFrame` and screen notification handling in `OverlayWindowManager`**

Update `Sources/StayCore/Services/OverlayWindowManager.swift`:
```swift
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
        guard let panel = panels[windowID] else { return }
        let screen = panel.screen ?? NSScreen.screens.first ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = screen?.visibleFrame ?? screenFrame

        let targetFrame = Self.calculateFrame(
            for: panel.target,
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
            let screen = panel.screen ?? NSScreen.screens.first ?? NSScreen.main
            let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            let visibleFrame = screen?.visibleFrame ?? screenFrame
            let targetFrame = Self.calculateFrame(
                for: panel.target,
                configuration: panel.configuration,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            )
            panel.applyConfiguration(panel.configuration, targetFrame: targetFrame, animated: false)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PeekerLayoutTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/Services/OverlayWindowManager.swift Tests/StayTests/PeekerLayoutTests.swift
git commit -m "feat(layout): add safe-area peeker frame calculation and screen reconfiguration listener"
```

---

### Task 3: Glassmorphic Hover Toolbar (`PeekerToolbarView`)

**Files:**
- Create: `Sources/StayCore/UI/PeekerToolbarView.swift`
- Test: `Tests/StayTests/PeekerToolbarTests.swift`

**Interfaces:**
- Consumes: `PeekerConfiguration`, `CornerPosition`, `PeekerDisplayMode`
- Produces: `PeekerToolbarView` (SwiftUI view with mode toggle, corner cycle, opacity slider, unpin action)

- [ ] **Step 1: Write unit tests for toolbar action handlers**

Create `Tests/StayTests/PeekerToolbarTests.swift`:
```swift
import Testing
import Foundation
@testable import StayCore

@Suite("Peeker Toolbar Tests")
struct PeekerToolbarTests {
    @Test("Toggle mode switches between inPlace and corner")
    func testToggleMode() {
        var config = PeekerConfiguration(mode: .corner(.bottomRight))
        if case .corner(let corner) = config.mode {
            config.mode = .inPlace
        } else {
            config.mode = .corner(.bottomRight)
        }
        #expect(config.mode == .inPlace)
    }

    @Test("Cycle corner advances to next corner")
    func testCycleCorner() {
        var corner = CornerPosition.bottomRight
        corner = corner.next
        #expect(corner == .bottomLeft)
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter PeekerToolbarTests`
Expected: PASS

- [ ] **Step 3: Implement `PeekerToolbarView` in SwiftUI**

Create `Sources/StayCore/UI/PeekerToolbarView.swift`:
```swift
import SwiftUI

public struct PeekerToolbarView: View {
    @Binding public var configuration: PeekerConfiguration
    public let onToggleMode: () -> Void
    public let onCycleCorner: () -> Void
    public let onUnpin: () -> Void

    public init(
        configuration: Binding<PeekerConfiguration>,
        onToggleMode: @escaping () -> Void,
        onCycleCorner: @escaping () -> Void,
        onUnpin: @escaping () -> Void
    ) {
        self._configuration = configuration
        self.onToggleMode = onToggleMode
        self.onCycleCorner = onCycleCorner
        self.onUnpin = onUnpin
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleMode) {
                Image(systemName: isCornerMode ? "arrow.up.left.and.arrow.down.right" : "pip")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .help(isCornerMode ? "Switch to 1:1 In-Place HUD (⌥⇧T)" : "Switch to Corner Thumbnail (⌥⇧T)")

            if isCornerMode {
                Button(action: onCycleCorner) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                        Text(cornerLabel)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                }
                .buttonStyle(.plain)
                .help("Cycle Screen Corner (⌥⇧C)")
            }

            Divider()
                .frame(height: 12)

            Slider(value: $configuration.opacity, in: 0.20...1.0)
                .frame(width: 60)
                .controlSize(.mini)
                .help("Adjust Transparency (\(Int(configuration.opacity * 100))%)")

            Divider()
                .frame(height: 12)

            Button(action: onUnpin) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Unpin Window")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }

    private var isCornerMode: Bool {
        if case .corner = configuration.mode { return true }
        return false
    }

    private var cornerLabel: String {
        guard case .corner(let corner) = configuration.mode else { return "" }
        switch corner {
        case .bottomRight: return "BR"
        case .bottomLeft:  return "BL"
        case .topLeft:     return "TL"
        case .topRight:    return "TR"
        }
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build`
Expected: Build complete!

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/UI/PeekerToolbarView.swift Tests/StayTests/PeekerToolbarTests.swift
git commit -m "feat(ui): add PeekerToolbarView with mode, corner cycle, and opacity controls"
```

---

### Task 4: Interactive `OverlayPanel` with Tracking Area & Event Routing

**Files:**
- Modify: `Sources/StayCore/UI/OverlayPanel.swift`
- Modify: `Sources/StayCore/Services/PinCoordinator.swift`
- Test: `Tests/StayTests/OverlayWindowManagerTests.swift`

**Interfaces:**
- Consumes: `PeekerToolbarView`, `OverlayWindowManager`
- Produces: `OverlayPanel.applyConfiguration`, mouse hover fade, hit-tested click delegation

- [ ] **Step 1: Write unit test verifying OverlayPanel configuration updates**

Update `Tests/StayTests/OverlayWindowManagerTests.swift`:
```swift
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

    @Test("OverlayPanel applies opacity and animated frame")
    func testApplyConfiguration() {
        let manager = OverlayWindowManager.shared
        let target = TargetWindow(
            id: 304,
            pid: 701,
            title: "Terminal",
            bundleID: "com.apple.Terminal",
            bounds: CGRect(x: 50, y: 50, width: 600, height: 400),
            role: "AXWindow"
        )
        let panel = manager.createOverlay(for: target, onClick: {})
        let newConfig = PeekerConfiguration(mode: .corner(.bottomLeft), opacity: 0.60)
        panel.applyConfiguration(newConfig, targetFrame: NSRect(x: 20, y: 20, width: 300, height: 200), animated: false)
        #expect(panel.alphaValue == 0.60)
        #expect(panel.frame.size.width == 300)
        manager.closeOverlay(for: 304)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OverlayWindowManagerTests`
Expected: FAIL with "type 'OverlayPanel' has no member 'applyConfiguration'"

- [ ] **Step 3: Implement `OverlayPanel` with tracking area, hosting view, and hit-testing**

Update `Sources/StayCore/UI/OverlayPanel.swift`:
```swift
import AppKit
import AVFoundation
import CoreMedia
import SwiftUI

public final class OverlayPanel: NSPanel {
    public let target: TargetWindow
    public private(set) var configuration: PeekerConfiguration
    public let displayLayer = AVSampleBufferDisplayLayer()
    private var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var toolbarHost: NSHostingView<AnyView>?

    public init(
        frame: NSRect,
        target: TargetWindow,
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
                guard let self else { return }
                var nextConfig = self.configuration
                switch nextConfig.mode {
                case .corner: nextConfig.mode = .inPlace
                case .inPlace: nextConfig.mode = .corner(.bottomRight)
                }
                OverlayWindowManager.shared.updateConfiguration(nextConfig, for: self.target.id)
            },
            onCycleCorner: { [weak self] in
                guard let self else { return }
                var nextConfig = self.configuration
                if case .corner(let corner) = nextConfig.mode {
                    nextConfig.mode = .corner(corner.next)
                    OverlayWindowManager.shared.updateConfiguration(nextConfig, for: self.target.id)
                }
            },
            onUnpin: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    await PinCoordinator.shared.unpin(windowID: self.target.id)
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
```

Update `PinCoordinator.swift` to pass `session.configuration` into `OverlayWindowManager.createOverlay`:
```swift
        let overlay = OverlayWindowManager.shared.createOverlay(for: target, configuration: session.configuration) {
            if let app = NSRunningApplication(processIdentifier: target.pid) {
                app.activate()
            }
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OverlayWindowManagerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/UI/OverlayPanel.swift Sources/StayCore/Services/PinCoordinator.swift Tests/StayTests/OverlayWindowManagerTests.swift
git commit -m "feat(panel): add hover glass toolbar, hit-testing separation, and animated applyConfiguration"
```

---

### Task 5: Global Hotkeys & Menu Bar Integration

**Files:**
- Modify: `Sources/StayCore/Services/HotkeyService.swift`
- Modify: `Sources/StayCore/Services/PinCoordinator.swift`
- Modify: `Sources/Stay/Views/PinnedCardView.swift`
- Modify: `Sources/Stay/Views/MenuBarView.swift`
- Test: `Tests/StayTests/HotkeyServiceTests.swift`

**Interfaces:**
- Consumes: `PinCoordinator`, `HotkeyService`
- Produces: `⌥⇧T` (Toggle 1:1 vs Corner), `⌥⇧C` (Cycle Corner), Menu Bar segmented controls

- [ ] **Step 1: Write test for new hotkey registration**

Update `Tests/StayTests/HotkeyServiceTests.swift`:
```swift
import Testing
@testable import StayCore

@Suite("HotkeyService Tests")
@MainActor
struct HotkeyServiceTests {
    @Test("Registration does not crash without Carbon event loop")
    func testRegistrationSafety() {
        let service = HotkeyService.shared
        service.register(onTogglePin: {}, onToggleMode: {}, onCycleCorner: {})
        #expect(true)
        service.unregister()
    }
}
```

- [ ] **Step 2: Implement hotkey expansion in `HotkeyService` and actions in `PinCoordinator`**

Update `Sources/StayCore/Services/HotkeyService.swift`:
```swift
import Foundation
import Carbon

@MainActor
public final class HotkeyService {
    public static let shared = HotkeyService()

    private var pinHotKeyRef: EventHotKeyRef?
    private var modeHotKeyRef: EventHotKeyRef?
    private var cornerHotKeyRef: EventHotKeyRef?

    private var onTogglePin: (@MainActor () -> Void)?
    private var onToggleMode: (@MainActor () -> Void)?
    private var onCycleCorner: (@MainActor () -> Void)?

    private init() {}

    public func register(
        onTogglePin: @escaping @MainActor () -> Void,
        onToggleMode: @escaping @MainActor () -> Void = {},
        onCycleCorner: @escaping @MainActor () -> Void = {}
    ) {
        self.onTogglePin = onTogglePin
        self.onToggleMode = onToggleMode
        self.onCycleCorner = onCycleCorner

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            guard let event = eventRef else { return noErr }
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            Task { @MainActor in
                switch hotKeyID.id {
                case 1: HotkeyService.shared.onTogglePin?()
                case 2: HotkeyService.shared.onToggleMode?()
                case 3: HotkeyService.shared.onCycleCorner?()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        // ⌥⇧P: kVK_ANSI_P (0x23)
        let pinID = EventHotKeyID(signature: OSType(0x53544159), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(optionKey | shiftKey), pinID, GetApplicationEventTarget(), 0, &pinHotKeyRef)

        // ⌥⇧T: kVK_ANSI_T (0x11)
        let modeID = EventHotKeyID(signature: OSType(0x53544159), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(optionKey | shiftKey), modeID, GetApplicationEventTarget(), 0, &modeHotKeyRef)

        // ⌥⇧C: kVK_ANSI_C (0x08)
        let cornerID = EventHotKeyID(signature: OSType(0x53544159), id: 3)
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(optionKey | shiftKey), cornerID, GetApplicationEventTarget(), 0, &cornerHotKeyRef)
    }

    public func unregister() {
        if let ref = pinHotKeyRef { UnregisterEventHotKey(ref); pinHotKeyRef = nil }
        if let ref = modeHotKeyRef { UnregisterEventHotKey(ref); modeHotKeyRef = nil }
        if let ref = cornerHotKeyRef { UnregisterEventHotKey(ref); cornerHotKeyRef = nil }
    }
}
```

Add convenience toggles to `Sources/StayCore/Services/PinCoordinator.swift`:
```swift
    public func toggleActiveMode() {
        guard let firstSession = activeSessions.values.first else { return }
        var nextConfig = firstSession.configuration
        switch nextConfig.mode {
        case .corner: nextConfig.mode = .inPlace
        case .inPlace: nextConfig.mode = .corner(.bottomRight)
        }
        firstSession.configuration = nextConfig
        OverlayWindowManager.shared.updateConfiguration(nextConfig, for: firstSession.id)
    }

    public func cycleActiveCorner() {
        guard let firstSession = activeSessions.values.first else { return }
        var nextConfig = firstSession.configuration
        if case .corner(let corner) = nextConfig.mode {
            nextConfig.mode = .corner(corner.next)
            firstSession.configuration = nextConfig
            OverlayWindowManager.shared.updateConfiguration(nextConfig, for: firstSession.id)
        }
    }
```

Update `Sources/Stay/Views/PinnedCardView.swift` and `MenuBarView.swift` to reflect mode and corner controls.

- [ ] **Step 3: Run all unit tests to verify they pass**

Run: `swift test --test-product StayTests`
Expected: All tests pass!

- [ ] **Step 4: Commit**

```bash
git add Sources/StayCore/Services/HotkeyService.swift Sources/StayCore/Services/PinCoordinator.swift Sources/Stay/Views/PinnedCardView.swift Sources/Stay/Views/MenuBarView.swift Tests/StayTests/HotkeyServiceTests.swift
git commit -m "feat(hotkeys): add ⌥⇧T mode toggle and ⌥⇧C corner cycling hotkeys with menu bar card controls"
```

---

### Task 6: Full Verification, Bundle Build & App Signing

**Files:**
- Run: `swift test --test-product StayTests`
- Run: `./scripts/build_app.sh`
- Artifact: `./Stay.app`

- [ ] **Step 1: Run full test suite**

Run: `swift test --test-product StayTests`
Expected: 8+ passing test suites.

- [ ] **Step 2: Build release application bundle**

Run: `bash ./scripts/build_app.sh`
Expected: Exit code 0, signed `Stay.app` generated.

- [ ] **Step 3: Commit and push**

```bash
git add .
git commit -m "chore: release Developer Reference Peeker update for Stay.app"
```
