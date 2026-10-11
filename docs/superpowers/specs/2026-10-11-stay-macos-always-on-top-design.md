# Stay: macOS "Always on Top" Architecture & System Specification

- **Target Platforms:** macOS 14 (Sonoma) and macOS 15 (Sequoia)
- **Language / Runtime:** Swift 6 (Strict Concurrency, `async/await`, Actors)
- **UI Frameworks:** SwiftUI (`MenuBarExtra`), AppKit (`NSPanel`, `AVSampleBufferDisplayLayer`)
- **System Frameworks:** ScreenCaptureKit, ApplicationServices (Accessibility), Carbon (HotKeys), CoreGraphics
- **Date:** 2026-10-11
- **Status:** Approved / Ready for Implementation

---

## 1. Executive Summary & Problem Context

macOS does not provide a native public or private API that allows an external process to arbitrarily elevate another application's window to `NSWindow.Level.floating` while maintaining normal window hierarchy.

Empirical testing on macOS via [StayProbe](file:///Users/arshnirmal/Desktop/arsh/Projects/Stay/Sources/StayProbe/Main.swift) confirmed:
1. **`kAXRaiseAction` Limitation:** `AXUIElementPerformAction(element, kAXRaiseAction)` returns success in 2.7ms, but only orders windows *within the target process's internal window stack*. macOS Window Server refuses to order an inactive background window above the active frontmost application.
2. **`SkyLight` Private API Limitation:** Calling `SLSSetWindowLevel` or `SLSOrderWindow` from an external connection returns `kCGErrorSuccess` (0) but is silently discarded by Window Server due to Mach port connection ownership checks.
3. **Accessibility Timer Loop Failure:** Simulating an activation loop (used by tools like Abhishek Olkha's `AlwaysOnTop`) results in severe **focus stealing**, interrupting active typing in background apps.
4. **Dylib Injection Failure:** Injecting code into target processes (legacy `Afloat` / `Yabai load-sa`) requires disabling System Integrity Protection (`csrutil disable`), which is completely unviable for consumer software.

### The Solution
Stay adopts the **Hardware-Accelerated Zero-Copy Floating Mirror with Smart Focus Hand-off**. Stay creates its own native `NSPanel` at `window.level = .floating`. It streams the target window in real-time using `ScreenCaptureKit` directly into an `AVSampleBufferDisplayLayer`. Because Stay owns the panel, Window Server guarantees it will never be buried. 

By employing **Smart State Gating**, streaming is automatically paused whenever the user works inside the target app, reducing active energy overhead to **0.0% CPU and 0.0W power**.

---

## 2. Goals & Non-Goals

### Goals
* **True Burial Immunity:** The pinned window remains 100% visible above any active application without flickering.
* **Zero Focus Stealing:** The user types uninterrupted in their active background applications.
* **Ultra-Low Battery & Performance Impact:**
  * Zero memory bandwidth copies (direct GPU `IOSurface` textures).
  * 0.0% CPU / 0.0W power when interacting with the pinned window.
  * < 0.5% CPU when streaming static productivity apps.
* **Modern macOS UI/UX:** Native SwiftUI `MenuBarExtra`, floating HUD feedback pill, custom opacity slider, and ProMotion (120Hz) frame synchronization.
* **100% SIP Compatibility:** Fully compatible with System Integrity Protection enabled.

### Non-Goals
* Backward compatibility with macOS 13 (Ventura) or earlier.
* Code injection or SIMBL-style hacks.
* Arbitrary window resizing of non-resizable system dialogs.

---

## 3. System Architecture & Component Model

```text
┌────────────────────────────────────────────────────────┐
│                        StayApp                         │
│       (SwiftUI MenuBarExtra + Dynamic HUD Overlay)     │
└───────────────▲────────────────────────▲───────────────┘
                │                        │
       [User Actions / UI]       [Published State]
                │                        │
┌───────────────▼────────────────────────┴───────────────┐
│                    PinCoordinator                      │
│     (@MainActor State Coordinator & Session Tracker)   │
└──────┬──────────────┬───────────────┬──────────────┬───┘
       │              │               │              │
┌──────▼──────┐┌──────▼──────┐ ┌──────▼──────┐┌──────▼──────┐
│Window       ││CaptureEngine│ │OverlayWindow││SmartFocus   │
│Discovery    ││(SCStream &  │ │Manager      ││SyncService  │
│Service      ││Zero-Copy    │ │(NSPanel &   ││(Target focus│
│(AX / CG     ││CMSample-    │ │AVSample-    ││ detection & │
│ resolution) ││ Buffer)     │ │BufferLayer) ││ auto-pause) │
└─────────────┘└─────────────┘ └─────────────┘└─────────────┘
       │                                             │
┌──────▼──────┐                               ┌──────▼──────┐
│HotkeyService│                               │PowerManager │
│(Carbon HotKey                               │(Low Power   │
│ listener)   │                               │ & FPS scale)│
└─────────────┘                               └─────────────┘
```

### Component Specifications

#### 3.1 `PinCoordinator` (`@MainActor`)
* Manages the lifecycle of active sessions: `var activeSessions: [CGWindowID: PinSession]`.
* Provides public methods:
  * `toggleActiveWindow() async throws`
  * `pin(window: TargetWindow) async throws`
  * `unpin(windowID: CGWindowID)`
  * `unpinAll()`
* Observes `NSWorkspace.didTerminateApplicationNotification` to automatically tear down sessions when a pinned application exits.

#### 3.2 `CaptureEngine` (Actor)
* Encapsulates `ScreenCaptureKit` stream lifecycle.
* Configures `SCContentFilter` targeting only the specific `SCWindow`.
* Sets `SCStreamConfiguration`:
  * `pixelFormat = kCVPixelFormatType_32BGRA`
  * `queueDepth = 1` (drops stale frames to eliminate latency)
  * `capturesAudio = false`
  * `showsCursor = true`
  * `minimumFrameInterval = CMTime(value: 1, timescale: targetFPS)`
* Implements `SCStreamOutput` and routes `CMSampleBuffer` directly to the display layer via a dedicated serial dispatch queue (`qos: .userInteractive`).

#### 3.3 `OverlayWindowManager` (`@MainActor`)
* Spawns an `OverlayPanel: NSPanel` configured with:
  * `level = .floating`
  * `styleMask = [.borderless, .nonactivatingPanel]`
  * `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
  * `isOpaque = false`
  * `backgroundColor = .clear`
  * `hasShadow = true`
* Hosts an `AVSampleBufferDisplayLayer` as the root backing layer.
* Maintains a subtle 1.5pt accent border ring.
* Listens to `AXObserver` events (`kAXWindowMovedNotification`, `kAXWindowResizedNotification`) on the target window to mirror geometry instantaneously.

#### 3.4 `SmartFocusSyncService`
* Subscribes to `NSWorkspace.didActivateApplicationNotification`.
* **State Transition:**
  * When `frontApp.pid == session.targetPID`: Pauses `SCStream` and hides `OverlayPanel`. (Overhead = 0.0%).
  * When `frontApp.pid != session.targetPID`: Resumes `SCStream` and shows `OverlayPanel`.

#### 3.5 `HotkeyService`
* Registers global hotkeys using Carbon `RegisterEventHotKey` (Default: `⌥⌘T`).
* Does not require Accessibility Input Monitoring permissions.

#### 3.6 `PowerManager`
* Observes `ProcessInfo.processInfo.isLowPowerModeEnabled` and AC vs Battery state.
* Adjusts target FPS:
  * **On Battery / Low Power:** 15 FPS.
  * **On Battery / Normal:** 30 FPS.
  * **On AC Power:** 60 FPS (or 120 FPS on ProMotion).

---

## 4. Zero-Copy Pipeline & State Transitions

### 4.1 Frame Composition Pipeline
```text
[WindowServer / Target App GPU Framebuffer]
               │
               ▼ (Zero-Copy Texture Share)
   [ScreenCaptureKit: SCStream]
               │
               ▼ (CMSampleBuffer referencing IOSurface)
  [High-Priority GCD Serial Queue]
               │
               ▼ (Enqueued directly)
  [AVSampleBufferDisplayLayer]
               │
               ▼ (Hardware Composited by GPU)
         [Retina Display]
```

### 4.2 State Machine
1. **`IDLE`:** No active pins. CPU: 0%, GPU: 0%.
2. **`PINNING`:** User presses `⌥⌘T`. Frontmost window resolved via `WindowDiscoveryService`. Stream initialized.
3. **`ACTIVE: STREAMING`:** User switches to another application. Overlay visible. Target window content mirrored in real-time.
4. **`ACTIVE: PAUSED`:** User activates the target application. Stream paused, overlay hidden. User interacts natively with zero proxy lag.
5. **`UNPINNED`:** Stream stopped, `NSPanel` closed and released.

---

## 5. UI/UX & Interaction Design

### 5.1 Menu Bar Interface
* **Status Item:** SF Symbol `pin` (outlined when idle, filled accent color when active).
* **Menu Bar Popover:**
  * Header showing active count: *"Pinned Windows (1)"*.
  * List of active cards with application icon, window title, opacity slider (20% – 100%), and unpin button.
  * Quick shortcuts reference: `⌥⌘T` (Pin/Unpin Active), `⌥⌘K` (Toggle Click-Through), `⌥⇧⌘T` (Unpin All).
  * System status: Permissions indicator and Low Power indicator.

### 5.2 Dynamic HUD Pill
* Transient 1.2-second floating pill at top-center of screen confirming actions:
  * *"📌 Safari Pinned"*
  * *"📍 Safari Unpinned"*
  * *"👻 Click-Through Active"*
* Triggers subtle haptic feedback via `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)`.

### 5.3 Interaction Modes
* **Mode A: Smart Focus on Click (Default):**
  * Clicking anywhere on the floating mirror smoothly calls `NSRunningApplication.activate(options: .activateIgnoringOtherApps)`.
  * Instantly brings native window to the front under the cursor for full keyboard/mouse interaction.
* **Mode B: Click-Through Reference:**
  * Sets `panel.ignoresMouseEvents = true`.
  * Clicks pass straight through to whatever is behind the window. Perfect for reference notes and coding docs.

---

## 6. Error Handling, Edge Cases & Lifecycle

| Scenario | System Behavior |
| :--- | :--- |
| **Target Window Closed (`⌘W`)** | `kAXUIElementDestroyedNotification` fires; session immediately torn down; overlay closed. |
| **Target App Quits (`⌘Q`)** | `NSWorkspace.didTerminateApplicationNotification` fires; session removed cleanly with zero memory leaks. |
| **Target Minimized (`⌘M`)** | `kAXWindowMiniaturizedNotification` temporarily hides overlay until restored. |
| **Spaces / Full-screen Swipes** | `.canJoinAllSpaces` and `.fullScreenAuxiliary` allow the overlay to remain visible across virtual desktops. |
| **Display Reconnection** | `didChangeScreenParametersNotification` recalculates backing scale factor and screen bounds. |
| **Permissions Revoked** | Detects permission loss; displays actionable banner linking to macOS Privacy Settings. |

---

## 7. Testing & Verification Strategy

### 7.1 Automated Unit Tests
* **`PinCoordinatorTests`:** Verify idempotent session registration, unpinning, and state transitions.
* **`WindowEligibilityTests`:** Verify system menus, Dock, and background daemons are filtered out.
* **`PowerManagerTests`:** Verify FPS throttle adjustments when Low Power flags toggle.

### 7.2 CLI Diagnostic Probes
* Re-usable diagnostic command: `stay --verify-sc-stream <wid>` to benchmark latency and confirm `IOSurface` backing.

### 7.3 Acceptance Matrix
1. **Burial Immunity:** Target remains visible when background app is clicked.
2. **Focus Preservation:** Typing in background app is 100% uninterrupted.
3. **0.0% CPU at Rest:** Activity Monitor confirms 0% CPU while working in the pinned app.
4. **Instant Teardown:** Closing target window immediately frees overlay.
5. **Global Hotkey:** `⌥⌘T` responds in < 30ms from any app.
