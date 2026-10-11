# Developer Reference Peeker Design Specification

- **Date:** 2026-10-11
- **Status:** Approved
- **Target Platform:** macOS 14.0+ (Sonoma, Sequoia)
- **Architecture:** Swift 6, AppKit, ScreenCaptureKit, SwiftUI

---

## 1. Overview & Context

Streaming media services (Netflix, Amazon Prime Video, Disney+ Hotstar) rely on hardware DRM CDMs (Widevine / FairPlay) which deliberately black out third-party screen-capture pipelines, but are natively supported via browser Picture-in-Picture (`kCGPIPWindowLevel`).

**Stay** pivots from general media mirroring to a specialized **Developer Reference Peeker**. It provides a frictionless, high-performance floating companion for developers multitasking between full-screen IDEs and auxiliary tools (Terminal build watchers, test runners, iOS Simulator, API specs, Figma designs, and notes).

### Core Goals
1. **Dual Display Modes**:
   - **Corner Thumbnail**: Compact PiP-style mini-monitor (~30% screen width) docked cleanly in any screen corner without obscuring the main code workspace.
   - **1:1 In-Place HUD**: Full-size translucent overlay anchored directly over the original window frame for rapid context inspection.
2. **Fluid Interaction & Controls**:
   - Hover-activated glassmorphic toolbar with an opacity slider (20% to 100%), corner cycle button, and mode toggle.
   - **Smart Focus**: Clicking the preview body activates the underlying source application; interacting with toolbar controls adjusts settings without switching focus.
3. **Keyboard-Driven Workflow**:
   - `⌥⇧P`: Pin / Unpin active window.
   - `⌥⇧T`: Toggle between 1:1 In-Place HUD and Corner Thumbnail.
   - `⌥⇧C`: Cycle through screen corners (Bottom-Right → Bottom-Left → Top-Left → Top-Right).

---

## 2. Architecture & Data Models

### 2.1 Configuration Models (`StayCore/Models/`)

```swift
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
    public var opacity: CGFloat       // Clamped 0.20 ... 1.0 (default 0.90)
    public var scaleRatio: CGFloat     // 0.20 ... 0.45 (default 0.30)

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

### 2.2 Domain Session Updates
`PinSession` in `StayCore/Models/PinSession.swift` is updated to retain the active `PeekerConfiguration`:
```swift
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

---

## 3. Layout Engine & Coordinate Systems

### 3.1 Display Coordinate Geometry
macOS AppKit and Quartz WindowServer use opposing vertical coordinate conventions:
- **Quartz / CGWindowList**: Origin $(0, 0)$ is top-left of the primary display.
- **Cocoa / AppKit**: Origin $(0, 0)$ is bottom-left of the primary display.

To ensure overlays avoid covering the macOS Menu Bar and Dock, corner calculations utilize `screen.visibleFrame`:

1. **Aspect Ratio Preservation**:
   $$\text{aspectRatio} = \frac{\text{target.bounds.width}}{\text{target.bounds.height}}$$
   $$\text{cornerWidth} = \text{visibleFrame.width} \times \text{configuration.scaleRatio}$$
   $$\text{cornerHeight} = \frac{\text{cornerWidth}}{\text{aspectRatio}}$$

2. **Corner Anchors (16pt margin)**:
   - **Bottom-Right**:
     $$x = \text{visibleFrame.maxX} - \text{cornerWidth} - 16$$
     $$y = \text{visibleFrame.minY} + 16$$
   - **Bottom-Left**:
     $$x = \text{visibleFrame.minX} + 16$$
     $$y = \text{visibleFrame.minY} + 16$$
   - **Top-Right**:
     $$x = \text{visibleFrame.maxX} - \text{cornerWidth} - 16$$
     $$y = \text{visibleFrame.maxY} - \text{cornerHeight} - 16$$
   - **Top-Left**:
     $$x = \text{visibleFrame.minX} + 16$$
     $$y = \text{visibleFrame.maxY} - \text{cornerHeight} - 16$$

3. **In-Place Frame Calculation**:
   $$\text{primaryHeight} = (\text{NSScreen.screens.first} \text{ ?? } \text{NSScreen.main})?.frame.height \text{ ?? } 1080$$
   $$x = \text{target.bounds.origin.x}$$
   $$y = \text{primaryHeight} - \text{target.bounds.origin.y} - \text{target.bounds.height}$$

### 3.2 Smooth Animated Transitions
Mode and corner transitions animate using `NSAnimationContext` with a duration of `0.25s` and an ease-in-out timing curve:
```swift
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.25
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    panel.animator().setFrame(targetFrame, display: true)
}
```

---

## 4. UI & Interaction Layer

### 4.1 OverlayPanel Structure (`StayCore/UI/OverlayPanel.swift`)
The panel maintains a level of `.floating` with `.canJoinAllSpaces` and `.fullScreenAuxiliary` behavior:
1. **Background Layer**: Transparent with rounded corners (12pt corner radius) and a subtle 1.5pt accent border.
2. **Video Layer**: `AVSampleBufferDisplayLayer` enqueued with live BGRA frames from `ScreenCaptureKit`.
3. **Hover Toolbar Layer**: An `NSHostingView` hosting `PeekerToolbarView` anchored to the top of the panel.

### 4.2 Hover Glass Toolbar (`PeekerToolbarView`)
- Invisible by default (`opacity: 0`).
- Fades in with smooth animation (`0.2s ease-in-out`) on `mouseEntered` via `NSTrackingArea`.
- Fades out on `mouseExited`.
- Controls:
  - **Mode Toggle Button**: Switch between 1:1 In-Place and Corner Thumbnail.
  - **Corner Cycle Button**: Visible when in corner mode; cycles to the next corner.
  - **Opacity Slider**: Slider bounded between `0.20` and `1.0`, bound directly to `panel.alphaValue`.
  - **Unpin Button (X)**: Immediately stops stream and closes overlay.

### 4.3 Hit-Testing & Smart Focus
- **Toolbar Hits**: Events falling within the toolbar controls are handled by SwiftUI without triggering window switching.
- **Surface Hits**: Clicking the body outside the toolbar controls triggers `onClick`, activating the target application (`app.activate()`) and delegating control to the real app.

---

## 5. Hotkeys & Global Controls

### 5.1 Hotkey Bindings
Implemented via `HotkeyService` using Carbon Event Hotkeys:
- **`⌥⇧P`**: Pin / Unpin frontmost eligible window.
- **`⌥⇧T`**: Toggle between `.inPlace` and `.corner` for the active peeker session.
- **`⌥⇧C`**: Cycle `.corner` position (BR → BL → TL → TR).

### 5.2 Menu Bar Controls
The Menu Bar dropdown (`PinnedCardView`) reflects the active configuration:
- Mode picker (`1:1` vs `Corner`).
- Opacity slider.
- Corner grid selector.
- Unpin button.

---

## 6. Multi-Display & Lifecycle Management

1. **Screen Topology Changes**:
   Listens for `NSApplication.didChangeScreenParametersNotification`. Recalculates corner frames to prevent thumbnails from being orphaned off-screen if an external display is disconnected.
2. **Process Termination**:
   Listens for `NSWorkspace.didTerminateApplicationNotification`. If the target app terminates, the stream is halted and the overlay is closed immediately.

---

## 7. Testing Strategy

1. **`PeekerLayoutTests`**:
   - Verify corner coordinate calculations across standard display sizes (1080p, 1440p, 4K Retina).
   - Verify aspect ratio scaling and clamping behavior.
2. **`PeekerConfigurationTests`**:
   - Verify opacity clamping within `[0.20, 1.0]`.
   - Verify corner cycling sequence `bottomRight -> bottomLeft -> topLeft -> topRight -> bottomRight`.
3. **`OverlayWindowManagerTests`**:
   - Test frame updates during mode toggles.
   - Verify hit-testing separation between toolbar controls and surface clicks.
