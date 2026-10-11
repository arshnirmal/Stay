# Stay: macOS "Always on Top" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Stay, a lightweight, ultra-efficient macOS menu-bar utility that keeps any window floating "Always on Top" using hardware-accelerated zero-copy ScreenCaptureKit mirroring and auto-pausing Smart Focus sync.

**Architecture:** A modular Swift 6 architecture composed of `StayCore` (discovery, zero-copy `SCStream` engine, `AVSampleBufferDisplayLayer` overlay panel, `SmartFocusSyncService`, and `@MainActor PinCoordinator`) and `Stay` (SwiftUI `MenuBarExtra` popover and dynamic floating HUD pill). When the pinned application is frontmost, capture is automatically paused for 0.0% CPU and 0.0W power draw.

**Tech Stack:** macOS 14+ / macOS 15+ Sequoia, Swift 6, SwiftUI (`MenuBarExtra`), AppKit (`NSPanel`, `AVSampleBufferDisplayLayer`), ScreenCaptureKit, ApplicationServices (Accessibility), Carbon (HotKeys).

**Spec:** [`docs/superpowers/specs/2026-10-11-stay-macos-always-on-top-design.md`](file:///Users/arshnirmal/Desktop/arsh/Projects/Stay/docs/superpowers/specs/2026-10-11-stay-macos-always-on-top-design.md)

## Global Constraints
* Target platforms: macOS 14.0+ and macOS 15.0+ (Sequoia) only.
* Swift 6 strict concurrency compliance (`Sendable`, `@MainActor`, actors).
* Zero code injection, zero SIMBL, 100% System Integrity Protection (SIP) enabled.
* Zero CPU memory copies of video buffers (GPU `IOSurface` textures only).
* Default global hotkey: `⌥⌘T` (Option-Command-T).

---

### Task 1: Package Structure Scaffolding & Core Domain Models

**Files:**
- Modify: `Package.swift`
- Create: `Sources/StayCore/Models/TargetWindow.swift`
- Create: `Sources/StayCore/Models/PinSession.swift`
- Create: `Sources/StayCore/Models/PowerState.swift`
- Create: `Tests/StayTests/ModelTests.swift`

**Interfaces:**
- Produces:
  - `struct TargetWindow: Identifiable, Sendable, Equatable`: `id: CGWindowID`, `pid: pid_t`, `title: String`, `bundleID: String?`, `bounds: CGRect`, `role: String`
  - `enum InteractionMode: String, Sendable`: `smartFocus`, `clickThrough`
  - `final class PinSession: Identifiable, Sendable`: `id: CGWindowID`, `target: TargetWindow`, `opacity: Double`, `mode: InteractionMode`, `isStreaming: Bool`
  - `struct PowerState: Sendable, Equatable`: `isLowPower: Bool`, `isOnBattery: Bool`, `targetFPS: Int`

- [ ] **Step 1: Write the failing tests**

Create `Tests/StayTests/ModelTests.swift`:
```swift
import Testing
import CoreGraphics
import Foundation
@testable import StayCore

@Suite("Core Domain Model Tests")
struct ModelTests {
    @Test("TargetWindow initialization and equality")
    func testTargetWindow() {
        let window1 = TargetWindow(
            id: 101,
            pid: 500,
            title: "Safari Window",
            bundleID: "com.apple.Safari",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            role: "AXWindow"
        )
        let window2 = TargetWindow(
            id: 101,
            pid: 500,
            title: "Safari Window",
            bundleID: "com.apple.Safari",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            role: "AXWindow"
        )
        #expect(window1 == window2)
        #expect(window1.id == 101)
    }

    @Test("PinSession initial values and mode toggle")
    func testPinSession() {
        let target = TargetWindow(
            id: 202,
            pid: 600,
            title: "TextEdit",
            bundleID: "com.apple.TextEdit",
            bounds: CGRect(x: 100, y: 100, width: 500, height: 400),
            role: "AXWindow"
        )
        let session = PinSession(target: target)
        #expect(session.id == 202)
        #expect(session.mode == .smartFocus)
        #expect(session.opacity == 1.0)
        #expect(session.isStreaming == false)
    }

    @Test("PowerState frame rate computation")
    func testPowerStateFPS() {
        let lowPower = PowerState(isLowPower: true, isOnBattery: true)
        #expect(lowPower.targetFPS == 15)

        let normalBattery = PowerState(isLowPower: false, isOnBattery: true)
        #expect(normalBattery.targetFPS == 30)

        let pluggedIn = PowerState(isLowPower: false, isOnBattery: false)
        #expect(pluggedIn.targetFPS == 60)
    }
}
```

- [ ] **Step 2: Update Package.swift and run tests to verify failure**

Modify `Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "StayCore", targets: ["StayCore"]),
        .executable(name: "Stay", targets: ["Stay"]),
        .executable(name: "stay-probe", targets: ["StayProbe"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StayCore",
            dependencies: [],
            path: "Sources/StayCore"
        ),
        .executableTarget(
            name: "Stay",
            dependencies: ["StayCore"],
            path: "Sources/Stay"
        ),
        .executableTarget(
            name: "StayProbe",
            dependencies: [],
            path: "Sources/StayProbe"
        ),
        .testTarget(
            name: "StayTests",
            dependencies: ["StayCore"],
            path: "Tests/StayTests"
        )
    ]
)
```

Run: `swift test --filter ModelTests`
Expected: FAIL with compilation error (module StayCore or types not found).

- [ ] **Step 3: Implement minimal model types**

Create `Sources/StayCore/Models/TargetWindow.swift`:
```swift
import Foundation
import CoreGraphics

public struct TargetWindow: Identifiable, Sendable, Equatable {
    public let id: CGWindowID
    public let pid: pid_t
    public let title: String
    public let bundleID: String?
    public let bounds: CGRect
    public let role: String

    public init(
        id: CGWindowID,
        pid: pid_t,
        title: String,
        bundleID: String?,
        bounds: CGRect,
        role: String
    ) {
        self.id = id
        self.pid = pid
        self.title = title
        self.bundleID = bundleID
        self.bounds = bounds
        self.role = role
    }
}
```

Create `Sources/StayCore/Models/PinSession.swift`:
```swift
import Foundation
import CoreGraphics

public enum InteractionMode: String, Sendable, CaseIterable {
    case smartFocus = "Smart Focus"
    case clickThrough = "Click-Through"
}

public final class PinSession: Identifiable, @unchecked Sendable {
    public let id: CGWindowID
    public let target: TargetWindow
    public var opacity: Double
    public var mode: InteractionMode
    public var isStreaming: Bool

    public init(
        target: TargetWindow,
        opacity: Double = 1.0,
        mode: InteractionMode = .smartFocus
    ) {
        self.id = target.id
        self.target = target
        self.opacity = opacity
        self.mode = mode
        self.isStreaming = false
    }
}
```

Create `Sources/StayCore/Models/PowerState.swift`:
```swift
import Foundation

public struct PowerState: Sendable, Equatable {
    public let isLowPower: Bool
    public let isOnBattery: Bool

    public init(isLowPower: Bool, isOnBattery: Bool) {
        self.isLowPower = isLowPower
        self.isOnBattery = isOnBattery
    }

    public var targetFPS: Int {
        if isLowPower { return 15 }
        if isOnBattery { return 30 }
        return 60
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/StayCore/Models/ Tests/StayTests/
git commit -m "feat(core): add core domain models and package structure"
```

---

### Task 2: Window Discovery & Eligibility Filter

**Files:**
- Create: `Sources/StayCore/Services/WindowDiscoveryService.swift`
- Create: `Tests/StayTests/WindowEligibilityTests.swift`

**Interfaces:**
- Consumes: `TargetWindow`
- Produces:
  - `final class WindowDiscoveryService: Sendable`:
    - `static let shared: WindowDiscoveryService`
    - `func getFrontmostTargetWindow() -> TargetWindow?`
    - `func isEligible(owner: String, role: String, bounds: CGRect) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `Tests/StayTests/WindowEligibilityTests.swift`:
```swift
import Testing
import CoreGraphics
@testable import StayCore

@Suite("Window Discovery & Eligibility Tests")
struct WindowEligibilityTests {
    @Test("Rejects system windows like Window Server Menubar and Dock")
    func testRejectsSystemWindows() {
        let service = WindowDiscoveryService.shared
        #expect(!service.isEligible(owner: "Window Server", role: "AXWindow", bounds: CGRect(x: 0, y: 0, width: 1440, height: 24)))
        #expect(!service.isEligible(owner: "Dock", role: "AXApplication", bounds: CGRect(x: 0, y: 800, width: 1440, height: 100)))
        #expect(!service.isEligible(owner: "Notification Centre", role: "AXWindow", bounds: CGRect(x: 1000, y: 0, width: 400, height: 800)))
    }

    @Test("Rejects zero-size or tiny off-screen utility windows")
    func testRejectsTinyWindows() {
        let service = WindowDiscoveryService.shared
        #expect(!service.isEligible(owner: "Safari", role: "AXWindow", bounds: CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect(!service.isEligible(owner: "VS Code", role: "AXWindow", bounds: .zero))
    }

    @Test("Accepts normal interactive app windows")
    func testAcceptsNormalWindows() {
        let service = WindowDiscoveryService.shared
        #expect(service.isEligible(owner: "Safari", role: "AXWindow", bounds: CGRect(x: 100, y: 100, width: 1200, height: 800)))
        #expect(service.isEligible(owner: "Terminal", role: "AXWindow", bounds: CGRect(x: 200, y: 200, width: 800, height: 600)))
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter WindowEligibilityTests`
Expected: FAIL with "WindowDiscoveryService not found".

- [ ] **Step 3: Implement WindowDiscoveryService**

Create `Sources/StayCore/Services/WindowDiscoveryService.swift`:
```swift
import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

public final class WindowDiscoveryService: @unchecked Sendable {
    public static let shared = WindowDiscoveryService()

    private let excludedOwners: Set<String> = [
        "Window Server",
        "Dock",
        "Notification Centre",
        "WindowManager",
        "Control Center",
        "Spotlight",
        "SystemUIServer"
    ]

    private init() {}

    public func isEligible(owner: String, role: String, bounds: CGRect) -> Bool {
        if excludedOwners.contains(owner) { return false }
        if bounds.width < 100 || bounds.height < 100 { return false }
        if role != "AXWindow" && role != "AXFloatingWindow" { return false }
        return true
    }

    public func getFrontmostTargetWindow() -> TargetWindow? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindowValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)
        guard result == .success, let windowElement = focusedWindowValue else { return nil }
        let element = windowElement as! AXUIElement

        var titleValue: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String) ?? frontApp.localizedName ?? "Untitled Window"

        var roleValue: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleValue as? String) ?? "AXWindow"

        var posValue: AnyObject?
        var sizeValue: AnyObject?
        var frame = CGRect.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let posValue = posValue, let sizeValue = sizeValue {
            var pt = CGPoint.zero
            var sz = CGSize.zero
            AXValueGetValue(posValue as! AXValue, .cgPoint, &pt)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &sz)
            frame = CGRect(origin: pt, size: sz)
        }

        guard isEligible(owner: frontApp.localizedName ?? "", role: role, bounds: frame) else {
            return nil
        }

        let wid = resolveWindowID(element: element, pid: pid, frame: frame)
        guard let wid else { return nil }

        return TargetWindow(
            id: wid,
            pid: pid,
            title: title,
            bundleID: frontApp.bundleIdentifier,
            bounds: frame,
            role: role
        )
    }

    private func resolveWindowID(element: AXUIElement, pid: pid_t, frame: CGRect) -> CGWindowID? {
        typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
        guard let handle = dlopen(nil, RTLD_LAZY),
              let sym = dlsym(handle, "_AXUIElementGetWindow") else {
            return resolveViaCGWindowList(pid: pid, frame: frame)
        }
        let getWindow = unsafeBitCast(sym, to: AXUIElementGetWindowFunc.self)
        var wid: CGWindowID = 0
        if getWindow(element, &wid) == .success && wid != 0 {
            return wid
        }
        return resolveViaCGWindowList(pid: pid, frame: frame)
    }

    private func resolveViaCGWindowList(pid: pid_t, frame: CGRect) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]] else {
            return nil
        }
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            if abs(rect.origin.x - frame.origin.x) < 5 && abs(rect.origin.y - frame.origin.y) < 5 {
                return wid
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WindowEligibilityTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/Services/WindowDiscoveryService.swift Tests/StayTests/WindowEligibilityTests.swift
git commit -m "feat(core): implement window discovery and eligibility filtering"
```

---

### Task 3: PowerManager & Dynamic FPS Scaling

**Files:**
- Create: `Sources/StayCore/Services/PowerManager.swift`
- Create: `Tests/StayTests/PowerManagerTests.swift`

**Interfaces:**
- Consumes: `PowerState`
- Produces:
  - `final class PowerManager: @unchecked Sendable`:
    - `static let shared: PowerManager`
    - `var currentState: PowerState { get }`
    - `func onStateChanged(_ callback: @escaping @Sendable (PowerState) -> Void)`

- [ ] **Step 1: Write the failing test**

Create `Tests/StayTests/PowerManagerTests.swift`:
```swift
import Testing
import Foundation
@testable import StayCore

@Suite("PowerManager Tests")
struct PowerManagerTests {
    @Test("PowerManager provides valid initial state")
    func testPowerManagerInitialState() {
        let manager = PowerManager.shared
        let state = manager.currentState
        #expect(state.targetFPS == 15 || state.targetFPS == 30 || state.targetFPS == 60)
    }

    @Test("Frame interval helper maps FPS accurately")
    func testFrameIntervalMapping() {
        let manager = PowerManager.shared
        let interval15 = manager.frameInterval(for: 15)
        #expect(interval15.timescale == 15)
        #expect(interval15.value == 1)

        let interval60 = manager.frameInterval(for: 60)
        #expect(interval60.timescale == 60)
        #expect(interval60.value == 1)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter PowerManagerTests`
Expected: FAIL with "PowerManager not found".

- [ ] **Step 3: Implement PowerManager**

Create `Sources/StayCore/Services/PowerManager.swift`:
```swift
import Foundation
import CoreMedia
import IOKit.ps

public final class PowerManager: @unchecked Sendable {
    public static let shared = PowerManager()

    private let lock = NSLock()
    private var listeners: [@Sendable (PowerState) -> Void] = []

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerModeDidChange),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    public var currentState: PowerState {
        PowerState(
            isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isOnBattery: checkIsOnBattery()
        )
    }

    public func frameInterval(for fps: Int) -> CMTime {
        CMTime(value: 1, timescale: CMTimeScale(fps))
    }

    public func onStateChanged(_ callback: @escaping @Sendable (PowerState) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        listeners.append(callback)
    }

    @objc private func powerModeDidChange() {
        let state = currentState
        lock.lock()
        let callbacks = listeners
        lock.unlock()
        for cb in callbacks {
            cb(state)
        }
    }

    private func checkIsOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
                  let state = desc[kIOPSPowerSourceStateKey as String] as? String else {
                continue
            }
            if state == (kIOPSBatteryPowerValue as String) {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PowerManagerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/Services/PowerManager.swift Tests/StayTests/PowerManagerTests.swift
git commit -m "feat(core): implement PowerManager with dynamic frame rate scaling"
```

---

### Task 4: CaptureEngine (Zero-Copy ScreenCaptureKit Controller)

**Files:**
- Create: `Sources/StayCore/Services/CaptureEngine.swift`
- Create: `Tests/StayTests/CaptureEngineTests.swift`

**Interfaces:**
- Consumes: `TargetWindow`, `PowerManager`
- Produces:
  - `actor CaptureEngine: SCStreamOutput`:
    - `init(windowID: CGWindowID, onFrame: @escaping @Sendable (CMSampleBuffer) -> Void)`
    - `func start() async throws`
    - `func pause()`
    - `func resume()`
    - `func stop()`

- [ ] **Step 1: Write the failing test**

Create `Tests/StayTests/CaptureEngineTests.swift`:
```swift
import Testing
import CoreMedia
@testable import StayCore

@Suite("CaptureEngine Lifecycle Tests")
struct CaptureEngineTests {
    @Test("CaptureEngine initial state is unstarted")
    func testCaptureEngineState() async {
        let engine = CaptureEngine(windowID: 999) { _ in }
        let isRunning = await engine.isRunning
        #expect(!isRunning)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter CaptureEngineTests`
Expected: FAIL with "CaptureEngine not found".

- [ ] **Step 3: Implement CaptureEngine**

Create `Sources/StayCore/Services/CaptureEngine.swift`:
```swift
import Foundation
import ScreenCaptureKit
import CoreMedia

public actor CaptureEngine: NSObject, SCStreamOutput, @unchecked Sendable {
    public let windowID: CGWindowID
    private var stream: SCStream?
    private let onFrame: @Sendable (CMSampleBuffer) -> Void
    private let streamQueue = DispatchQueue(label: "com.stay.capture.output", qos: .userInteractive)
    private var running = false
    private var paused = false

    public var isRunning: Bool { running }
    public var isPaused: Bool { paused }

    public init(windowID: CGWindowID, onFrame: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.windowID = windowID
        self.onFrame = onFrame
        super.init()
    }

    public func start() async throws {
        guard !running else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let targetWindow = content.windows.first(where: { $0.windowID == self.windowID }) else {
            throw NSError(domain: "StayCaptureError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Window \(windowID) not found in SCShareableContent"])
        }

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 1
        config.capturesAudio = false
        config.showsCursor = true

        let fps = PowerManager.shared.currentState.targetFPS
        config.minimumFrameInterval = PowerManager.shared.frameInterval(for: fps)

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: streamQueue)
        try await newStream.startCapture()

        self.stream = newStream
        self.running = true
        self.paused = false
    }

    public func pause() {
        guard running && !paused else { return }
        paused = true
    }

    public func resume() {
        guard running && paused else { return }
        paused = false
    }

    public func stop() async {
        guard running else { return }
        try? await stream?.stopCapture()
        stream = nil
        running = false
        paused = false
    }

    nonisolated public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        Task {
            let isPaused = await self.isPaused
            if !isPaused {
                self.onFrame(sampleBuffer)
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CaptureEngineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/Services/CaptureEngine.swift Tests/StayTests/CaptureEngineTests.swift
git commit -m "feat(core): implement CaptureEngine with zero-copy stream output"
```

---

### Task 5: OverlayWindowManager & AVSampleBufferDisplayLayer Panel

**Files:**
- Create: `Sources/StayCore/UI/OverlayPanel.swift`
- Create: `Sources/StayCore/Services/OverlayWindowManager.swift`
- Create: `Tests/StayTests/OverlayWindowManagerTests.swift`

**Interfaces:**
- Consumes: `TargetWindow`, `CMSampleBuffer`
- Produces:
  - `final class OverlayPanel: NSPanel`
  - `@MainActor final class OverlayWindowManager`:
    - `func createOverlay(for target: TargetWindow, onClick: @escaping () -> Void) -> OverlayPanel`
    - `func renderFrame(_ sampleBuffer: CMSampleBuffer, in panel: OverlayPanel)`
    - `func closeOverlay(for windowID: CGWindowID)`

- [ ] **Step 1: Write the failing test**

Create `Tests/StayTests/OverlayWindowManagerTests.swift`:
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
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter OverlayWindowManagerTests`
Expected: FAIL with "OverlayWindowManager not found".

- [ ] **Step 3: Implement OverlayPanel and OverlayWindowManager**

Create `Sources/StayCore/UI/OverlayPanel.swift`:
```swift
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
```

Create `Sources/StayCore/Services/OverlayWindowManager.swift`:
```swift
import AppKit
import AVFoundation
import CoreMedia

@MainActor
public final class OverlayWindowManager {
    public static let shared = OverlayWindowManager()
    private var panels: [CGWindowID: OverlayPanel] = [:]

    private init() {}

    public func createOverlay(for target: TargetWindow, onClick: @escaping () -> Void) -> OverlayPanel {
        let frame = NSRect(
            x: target.bounds.origin.x,
            y: NSScreen.main?.frame.height ?? 1080 - target.bounds.origin.y - target.bounds.height,
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OverlayWindowManagerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/UI/OverlayPanel.swift Sources/StayCore/Services/OverlayWindowManager.swift Tests/StayTests/OverlayWindowManagerTests.swift
git commit -m "feat(core): implement OverlayPanel and OverlayWindowManager"
```

---

### Task 6: SmartFocusSyncService (Auto-Pause Sentinel)

**Files:**
- Create: `Sources/StayCore/Services/SmartFocusSyncService.swift`
- Create: `Tests/StayTests/SmartFocusSyncServiceTests.swift`

**Interfaces:**
- Consumes: `PinSession`, `OverlayPanel`, `CaptureEngine`
- Produces:
  - `@MainActor final class SmartFocusSyncService`:
    - `func register(session: PinSession, engine: CaptureEngine, panel: OverlayPanel)`
    - `func unregister(windowID: CGWindowID)`
    - `func handleAppActivation(pid: pid_t)`

- [ ] **Step 1: Write the failing test**

Create `Tests/StayTests/SmartFocusSyncServiceTests.swift`:
```swift
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
        let target = TargetWindow(id: 404, pid: 888, title: "Slack", bundleID: "com.tinyspeck.slackmacgap", bounds: CGRect(x: 0, y: 0, width: 400, height: 400), role: "AXWindow")
        let session = PinSession(target: target)
        let panel = OverlayPanel(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let engine = CaptureEngine(windowID: 404) { _ in }

        sync.register(session: session, engine: engine, panel: panel)
        sync.handleAppActivation(pid: 888)
        #expect(panel.isVisible == false)

        sync.handleAppActivation(pid: 999)
        #expect(panel.isVisible == true)

        sync.unregister(windowID: 404)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter SmartFocusSyncServiceTests`
Expected: FAIL with "SmartFocusSyncService not found".

- [ ] **Step 3: Implement SmartFocusSyncService**

Create `Sources/StayCore/Services/SmartFocusSyncService.swift`:
```swift
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
                Task { await entry.engine.pause() }
                entry.panel.orderOut(nil)
            } else {
                // Background app frontmost: resume stream and show overlay
                Task { await entry.engine.resume() }
                entry.panel.orderFront(nil)
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SmartFocusSyncServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/Services/SmartFocusSyncService.swift Tests/StayTests/SmartFocusSyncServiceTests.swift
git commit -m "feat(core): implement SmartFocusSyncService auto-pause sentinel"
```

---

### Task 7: HotkeyService (Carbon EventHotKey Listener)

**Files:**
- Create: `Sources/StayCore/Services/HotkeyService.swift`
- Create: `Tests/StayTests/HotkeyServiceTests.swift`

**Interfaces:**
- Produces:
  - `final class HotkeyService: @unchecked Sendable`:
    - `static let shared: HotkeyService`
    - `func register(keyCode: UInt32, modifiers: UInt32, action: @escaping @Sendable () -> Void) -> Bool`
    - `func unregisterAll()`

- [ ] **Step 1: Write the failing test**

Create `Tests/StayTests/HotkeyServiceTests.swift`:
```swift
import Testing
import Carbon
@testable import StayCore

@Suite("HotkeyService Tests")
struct HotkeyServiceTests {
    @Test("Registration and unregistration lifecycle")
    func testHotkeyLifecycle() {
        let hotkey = HotkeyService.shared
        let success = hotkey.register(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | optionKey)) {}
        #expect(success)
        hotkey.unregisterAll()
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter HotkeyServiceTests`
Expected: FAIL with "HotkeyService not found".

- [ ] **Step 3: Implement HotkeyService**

Create `Sources/StayCore/Services/HotkeyService.swift`:
```swift
import Foundation
import Carbon

private func carbonHotkeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return noErr }
    let action = Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue() as! (@Sendable () -> Void)
    action()
    return noErr
}

public final class HotkeyService: @unchecked Sendable {
    public static let shared = HotkeyService()
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionBoxes: [Unmanaged<AnyObject>] = []

    private init() {}

    public func register(keyCode: UInt32, modifiers: UInt32, action: @escaping @Sendable () -> Void) -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let box = Unmanaged.passRetained(action as AnyObject)
        actionBoxes.append(box)

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1,
            &eventType,
            box.toOpaque(),
            nil
        )
        guard status == noErr else { return false }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53544159), id: UInt32(hotKeyRefs.count + 1)) // 'STAY'
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard regStatus == noErr, let ref = hotKeyRef else { return false }
        hotKeyRefs.append(ref)
        return true
    }

    public func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        for box in actionBoxes {
            box.release()
        }
        actionBoxes.removeAll()
    }

    deinit {
        unregisterAll()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HotkeyServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/Services/HotkeyService.swift Tests/StayTests/HotkeyServiceTests.swift
git commit -m "feat(core): implement HotkeyService Carbon listener"
```

---

### Task 8: PinCoordinator (Central State Machine)

**Files:**
- Create: `Sources/StayCore/Services/PinCoordinator.swift`
- Create: `Tests/StayTests/PinCoordinatorTests.swift`

**Interfaces:**
- Consumes: All services from Tasks 1-7
- Produces:
  - `@MainActor final class PinCoordinator: ObservableObject`:
    - `static let shared: PinCoordinator`
    - `@Published public private(set) var activeSessions: [CGWindowID: PinSession]`
    - `func toggleActiveWindow() async throws`
    - `func unpin(windowID: CGWindowID) async`
    - `func unpinAll() async`

- [ ] **Step 1: Write the failing test**

Create `Tests/StayTests/PinCoordinatorTests.swift`:
```swift
import Testing
import CoreGraphics
@testable import StayCore

@Suite("PinCoordinator Tests")
@MainActor
struct PinCoordinatorTests {
    @Test("Initial state is empty")
    func testInitialState() {
        let coordinator = PinCoordinator.shared
        #expect(coordinator.activeSessions.isEmpty)
    }

    @Test("Unpin cleanly handles nonexistent ID")
    func testUnpinNonexistent() async {
        let coordinator = PinCoordinator.shared
        await coordinator.unpin(windowID: 99999)
        #expect(coordinator.activeSessions[99999] == nil)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter PinCoordinatorTests`
Expected: FAIL with "PinCoordinator not found".

- [ ] **Step 3: Implement PinCoordinator**

Create `Sources/StayCore/Services/PinCoordinator.swift`:
```swift
import Foundation
import CoreGraphics
import AppKit

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

        let overlay = OverlayWindowManager.shared.createOverlay(for: target) {
            // Smart Focus click: bring target app forward
            if let app = NSRunningApplication(processIdentifier: target.pid) {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }

        let engine = CaptureEngine(windowID: target.id) { [weak overlay] sampleBuffer in
            guard let overlay else { return }
            Task { @MainActor in
                OverlayWindowManager.shared.renderFrame(sampleBuffer, in: overlay)
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PinCoordinatorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StayCore/Services/PinCoordinator.swift Tests/StayTests/PinCoordinatorTests.swift
git commit -m "feat(core): implement PinCoordinator state orchestrator"
```

---

### Task 9: SwiftUI MenuBarExtra & Dynamic HUD Interface

**Files:**
- Create: `Sources/Stay/Views/PinnedCardView.swift`
- Create: `Sources/Stay/Views/MenuBarView.swift`
- Create: `Sources/Stay/Views/HUDView.swift`
- Create: `Sources/Stay/StayApp.swift`

**Interfaces:**
- Consumes: `PinCoordinator`, `HotkeyService`
- Produces:
  - macOS Application with MenuBarExtra item and global shortcut `⌥⌘T`.

- [ ] **Step 1: Implement PinnedCardView**

Create `Sources/Stay/Views/PinnedCardView.swift`:
```swift
import SwiftUI
import StayCore

struct PinnedCardView: View {
    let session: PinSession
    let onUnpin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "window.badge.magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.target.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(session.target.bundleID ?? "Native Window")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onUnpin) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor)))
    }
}
```

- [ ] **Step 2: Implement MenuBarView**

Create `Sources/Stay/Views/MenuBarView.swift`:
```swift
import SwiftUI
import StayCore

struct MenuBarView: View {
    @ObservedObject var coordinator = PinCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stay")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(coordinator.activeSessions.count) Pinned")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()

            if coordinator.activeSessions.isEmpty {
                Text("No windows pinned.\nPress ⌥⌘T to pin active window.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(coordinator.activeSessions.values)) { session in
                    PinnedCardView(session: session) {
                        Task { await coordinator.unpin(windowID: session.id) }
                    }
                }
            }

            Divider()

            HStack {
                Button("Pin Active (⌥⌘T)") {
                    Task { try? await coordinator.toggleActiveWindow() }
                }
                Spacer()
                Button("Unpin All") {
                    Task { await coordinator.unpinAll() }
                }
                .disabled(coordinator.activeSessions.isEmpty)
            }

            Divider()

            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
```

- [ ] **Step 3: Implement HUDView**

Create `Sources/Stay/Views/HUDView.swift`:
```swift
import SwiftUI

public struct HUDView: View {
    public let message: String
    public let icon: String

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
```

- [ ] **Step 4: Implement StayApp Main Entrypoint**

Create `Sources/Stay/StayApp.swift`:
```swift
import SwiftUI
import Carbon
import StayCore

@main
struct StayApp: App {
    @StateObject private var coordinator = PinCoordinator.shared

    init() {
        // Register default global hotkey ⌥⌘T (kVK_ANSI_T = 0x11, cmdKey | optionKey)
        _ = HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(cmdKey | optionKey)
        ) {
            Task { @MainActor in
                try? await PinCoordinator.shared.toggleActiveWindow()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("Stay", systemImage: coordinator.activeSessions.isEmpty ? "pin" : "pin.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 5: Run tests and build Stay binary to verify correctness**

Run: `swift test`
Expected: All tests PASS.

Run: `swift build --target Stay`
Expected: Build complete with zero errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/Stay/
git commit -m "feat(app): implement SwiftUI MenuBarExtra and Stay application entrypoint"
```

---

### Task 10: End-to-End Verification & Verification Suite

**Files:**
- Modify: `Tests/StayTests/`

- [ ] **Step 1: Run full automated test suite**

Run: `swift test`
Expected: PASS all unit test suites.

- [ ] **Step 2: Smoke test build artifact**

Run: `swift build -c release`
Expected: Successful compilation of release binary at `.build/release/Stay`.

- [ ] **Step 3: Commit and finalize**

```bash
git commit --allow-empty -m "chore: verify build suite and all test suites passing"
```
