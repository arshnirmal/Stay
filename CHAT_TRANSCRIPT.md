# Stay — ChatGPT Brainstorming & Architecture Discussion

> **Source**: [ChatGPT Conversation](https://chatgpt.com/share/6a9dac5a-2ee0-83ee-8905-e5297a651d28)

---

## Turn 1

### User

Is it possible for me to create an macOS app for window management like always on top feature?

### Assistant

Yes — absolutely. macOS gives you the APIs needed to build a window-management app with an **Always on Top** feature.

A practical version of the app could work like this:

- Select any currently open window.
- Press a global shortcut such as `⌥⌘T`.
- That window becomes **always on top**, even when you switch to another application.
- Press the shortcut again to release it.
- Optionally add window snapping, resizing, transparency, PiP-style behavior, workspace management, etc.

### The key macOS pieces

For a native Swift/SwiftUI app, the important APIs are:

**`NSWindow`**
Controls window behavior. The core of Always on Top is essentially setting the window's level to something like:

```swift
window.level = .floating
```

You can also use higher levels when appropriate.

**Accessibility APIs**
This is the important part people often overlook.

Your app generally cannot arbitrarily manipulate another application's windows just by using `NSWindow`, because those windows belong to another process. macOS Accessibility APIs (`AXUIElement`) allow an app with the appropriate Accessibility permission to inspect and manipulate other applications' windows.

That gives you functionality such as:

```text
Your App
   │
   ├── Detect active application
   │
   ├── Find its windows
   │
   ├── Identify selected window
   │
   └── Manipulate window through Accessibility API
```

**CGWindow APIs**
You can also use Core Graphics window information to enumerate windows and obtain information such as window IDs, bounds, owners, etc. These APIs are useful for discovering what's on screen, while Accessibility APIs are generally more useful for actually controlling another app's window.

### There is one important complication

Making **another application's existing window** truly "always on top" is harder than making your own window floating.

For example:

```text
YourAppWindow
    ↓
NSWindow.level = .floating
```

is straightforward.

But:

```text
Chrome window
    ↓
make Chrome window floating above everything
```

is not something you can simply accomplish by grabbing the `NSWindow` object, because Chrome's window belongs to Chrome's process.

You'd need to work through macOS's Accessibility/window-management mechanisms, and there are limitations depending on the application.

### This is actually a very good macOS project

Given what you've been working on with your **Windowd** idea previously, I'd structure it as a small native utility rather than trying to build a giant window manager immediately:

```text
Windowd
│
├── Menu Bar App
│
├── Global Hotkeys
│
├── Window Discovery
│   ├── Current window
│   ├── Visible windows
│   └── Application → windows
│
├── Window Actions
│   ├── Always on Top
│   ├── Move
│   ├── Resize
│   ├── Center
│   └── Close/Minimize
│
└── Settings
    ├── Shortcuts
    ├── Launch at Login
    └── Behavior
```

A **minimal MVP** could be surprisingly small:

```text
⌥⌘T
   ↓
Get currently focused window
   ↓
Identify window
   ↓
Toggle "Always on Top"
```

Then you could build toward something closer to **Rectangle + BetterTouchTool + window pinning**.

One particularly interesting feature would be **"Pin this window"**: you could pin a YouTube/terminal/Slack window and have it remain above other applications while still behaving like a normal window.

There are also macOS-specific considerations around **Accessibility permissions, sandboxing, notarization, and App Store distribution**, so where you intend to distribute it affects the architecture.

I can also lay out the **exact Swift/Xcode architecture and APIs needed to build the first working Always-on-Top prototype**, including the hardest part: controlling windows belonging to other apps.

---

## Turn 2

### User

Would this be memory and battery  efficient ? Also should i even be making this or just existing tools available in the market? Also note that should be very generic solution where in any window - finder or any browser or media play or whatsapp or etc. should work through this. Let’s ensure we adhere to industry best practices during implementation.
Feel free to ask questions for clarification or additional context.

### Assistant

Yes. And with your added requirement — **“pin any normal window: Finder, Safari/Chrome, WhatsApp, media players, Terminal, etc.”** — I think this is a technically worthwhile project, but I would **not** position it as “another window manager.”

The interesting product is a **small, generic window-control utility** whose first-class capability is *pinning arbitrary application windows*.

### 1. Memory and battery efficiency

It can be **extremely lightweight**.

The important architectural decision is to make it an **event-driven menu-bar utility**, not an application that continuously polls the screen.

A bad implementation would do something like:

```text
every 100 ms
    enumerate every window
    inspect every application
    compare positions
    update state
```

That would create unnecessary CPU/battery usage. Apple itself notes that generating system-window information through `CGWindowListCopyWindowInfo` is relatively expensive, so it shouldn't be called indiscriminately. 

A better architecture is:

```text
Windowd
│
├── Menu Bar process
│
├── Global hotkey listener
│
├── Accessibility event listener
│
├── Window state store
│
└── Window controller
       │
       ├── AXUIElement
       └── Core Graphics
```

Most of the time:

```text
CPU ≈ idle
Memory ≈ small
Battery impact ≈ negligible
```

The app wakes up when something actually happens:

```text
Hotkey pressed
       ↓
Determine focused window
       ↓
Toggle pin state
```

or when a relevant accessibility/window event occurs.

That's the architecture I'd target.

---

# 2. The generic-window requirement is achievable

Your requirement is exactly the right one:

> Finder should work.
> Chrome/Safari should work.
> WhatsApp should work.
> Terminal should work.
> VLC/IINA/etc. should work.
> Any ordinary application window should work.

The implementation should **not** contain application-specific logic such as:

```swift
if app == "Google Chrome" { ... }
if app == "Finder" { ... }
if app == "WhatsApp" { ... }
```

Instead, the abstraction should be:

```text
Focused Application
       ↓
Focused Window
       ↓
Window Identity
       ↓
Window State
       ↓
Pin / Unpin
```

macOS's Accessibility APIs are explicitly designed to allow assistive applications to communicate with and control accessible applications. `AXUIElement` is the underlying mechanism we'll want to build around. 

Core Graphics can provide information about the windows currently in the user's session, including window IDs and bounds. 

That combination gives us a reasonably generic foundation.

---

# 3. But there's an important technical caveat

I want to correct one thing from my previous answer.

For **your own application**, this is trivial:

```swift
window.level = .floating
```

Apple documents `.floating` as a standard window level, and floating windows appear above normal-level windows. 

For:

```text
Chrome
Finder
WhatsApp
```

we don't simply obtain their `NSWindow` object and set:

```swift
otherWindow.level = .floating
```

because **that window belongs to another process**.

That's the fundamental challenge.

Our application needs to interact with the target application through macOS's accessibility/window-management mechanisms.

And this means we need to design the application around a very important principle:

> **"Generic" should mean generic at the macOS window-system level, not guaranteed identical behavior for every application.**

There will inevitably be edge cases.

For example, an application may:

- expose incomplete Accessibility information
- use unusual/custom window implementations
- create transient windows
- behave differently in fullscreen
- have windows that macOS itself treats specially

We should build the product so that these cases **fail gracefully rather than crashing or doing something unpredictable**.

---

# 4. Should you build it when existing tools exist?

This is where I think the answer is interesting.

There are already several solutions:

**BetterTouchTool**  
Very powerful automation/customization platform.

**Rectangle Pro**  
Primarily a window-management tool, with additional functionality.

**Hammerspoon**  
Extremely flexible and scriptable.

And there are now products specifically marketed around pinning windows, such as Floaty. 

So:

### As a business idea?

I'd be cautious.

You're entering an established category.

### As a portfolio/open-source project?

**Absolutely.**

### As a polished personal utility that you might eventually distribute?

**Also yes.**

And there is still a real user problem: macOS currently doesn't expose a normal built-in "Always on Top" toggle for arbitrary application windows. Recent 2026 guides still describe third-party tools as the solution. 

---

# 5. Where I think your opportunity is

I wouldn't try to beat Rectangle at being Rectangle.

Instead:

### Existing tools

```text
               ┌──────────────────────┐
               │      Window Manager  │
               ├──────────────────────┤
               │ snapping             │
               │ resizing             │
               │ tiling               │
               │ spaces               │
               │ shortcuts            │
               │ automation            │
               │ layouts               │
               │ window pinning        │
               └──────────────────────┘
```

That's a huge product.

Your app could instead be:

```text
                 WINDOWD
                    │
          "Control any window"
                    │
        ┌───────────┴───────────┐
        │                       │
      Pin                   Unpin
        │
        ├── Always on top
        ├── Ignore fullscreen
        ├── Transparency
        ├── Click-through
        └── Remember state
```

That gives you a much clearer identity.

---

# 6. I'd actually change the MVP slightly

Instead of building a giant window manager, I'd make **v1 essentially one magical interaction**:

### Select a window → `⌥⌘T`

That's it.

For example:

```text
You're working in VS Code.

           VS Code
┌─────────────────────────────┐
│ code                         │
│                              │
│                              │
└─────────────────────────────┘


Press ⌥⌘T


VS Code becomes pinned.


Open Chrome
↓
Open Slack
↓
Open Finder
↓
Open Terminal


VS Code remains visible.
```

Then:

```text
⌥⌘T
```

again:

```text
Unpin
```

The user shouldn't need to open a separate UI.

That's what would make the utility feel **native and macOS-like**.

---

# 7. Then build the feature set incrementally

I'd structure the roadmap something like:

### V0 — Proof of concept

```text
Global hotkey
     ↓
Focused window
     ↓
Pin
     ↓
Unpin
```

### V1 — Reliable utility

Add:

```text
Menu bar icon

Pinned-window indicator

Persistence

Launch at login

Accessibility permission onboarding

Crash-safe state restoration
```

### V1.5

```text
Pin multiple windows

Per-window shortcuts

Window picker

Temporary pin
```

### V2

This is where it gets genuinely interesting:

```text
Pin above fullscreen apps
Transparency
Click-through
"Peek" mode
Auto-pin by application
Auto-pin by title
Pin across Spaces
```

Eventually:

```text
"Pin this window until I close it"

"Pin Chrome video while I'm coding"

"Keep this terminal visible on every Space"
```

---

# 8. Industry-best-practice architecture

Since you explicitly want this built properly, I'd strongly recommend **native Swift**, not Electron, Python, or a web wrapper.

Something like:

```text
Windowd/
│
├── App/
│   ├── WindowdApp.swift
│   ├── AppDelegate.swift
│   └── MenuBarController.swift
│
├── Core/
│   ├── Window.swift
│   ├── WindowID.swift
│   ├── WindowState.swift
│   └── Application.swift
│
├── Services/
│   ├── AccessibilityService.swift
│   ├── WindowDiscoveryService.swift
│   ├── WindowControlService.swift
│   ├── HotkeyService.swift
│   └── PermissionService.swift
│
├── Features/
│   ├── Pinning/
│   ├── WindowPicker/
│   └── Settings/
│
└── Infrastructure/
    ├── Logger.swift
    └── Persistence.swift
```

And most importantly:

```text
UI
 │
 ▼
Application Services
 │
 ▼
Window Domain Model
 │
 ▼
macOS Adapters
 ├── Accessibility
 └── Core Graphics
```

This keeps macOS-specific implementation details out of the rest of the application.

---

# 9. Privacy should be a first-class concern

This application will request **Accessibility permission**, which is a significant trust boundary.

Apple's Accessibility APIs allow applications to communicate with and control other applications, so users should know exactly why you're requesting that permission. 

Our design should therefore follow:

```text
NO SERVER
NO ACCOUNT
NO ANALYTICS BY DEFAULT
NO SCREEN CAPTURE
NO CONTENT COLLECTION
NO NETWORK REQUIRED
```

The app should ideally work entirely locally.

That becomes a strong product message:

> **Your windows never leave your Mac.**

We should also avoid Screen Recording permission unless a feature genuinely requires it. For basic window control, we should not unnecessarily request additional permissions.

And Apple's App Sandbox imposes restrictions on access to protected resources, so distribution/signing architecture needs to be considered from the beginning rather than bolted on later. 

---

# 10. The biggest thing I'd want to solve

Not CPU.

Not memory.

Not even the UI.

The hardest part is:

> **How do we reliably identify and control arbitrary third-party windows across modern macOS?**

That's the engineering challenge worth exploring.

I'd specifically test:

```text
Finder
Safari
Chrome
Firefox
Arc
Terminal
iTerm2
VS Code
Slack
WhatsApp
Discord
Spotify
VLC
IINA
Preview
System Settings
```

on current macOS versions and different window states:

```text
Normal
Minimized
Maximized
Fullscreen
Multiple Spaces
Multiple monitors
Stage Manager
Mission Control
Sleep/wake
App restart
Window recreation
```

That's where we'd discover what **"generic" actually means in practice**.

---

# 11. My recommendation

I **would build it**, but I would build it as a **focused native macOS utility**, not as another giant window manager.

The project is particularly good because it touches several genuinely interesting macOS engineering concepts:

```text
Swift
  +
AppKit
  +
Accessibility APIs
  +
Core Graphics
  +
Global keyboard events
  +
Window management
  +
macOS permissions
  +
Sandboxing
  +
Code signing / notarization
```

And we can keep the first version extremely small.

The goal I'd set is:

> **A ~5–10 MB native menu-bar utility that lets you pin almost any macOS application window with one global shortcut, with near-zero idle CPU activity and no network dependency.**

That is a much more interesting engineering project than simply cloning Rectangle.

One thing I would **not** do yet is start writing the code. First I'd like to establish the exact macOS window-control mechanism and test its behavior across the applications above; that will determine whether our "any window" promise is technically sound before we commit to the architecture. Apple provides the underlying window enumeration and Accessibility primitives, but the interaction between them is where the real implementation details lie. 

---

## Turn 3

### User

Got it, Looks good. The Windowd was a claude's session window management project. So what should name of this project? Should this extend Windowd? or new? What should be the tech stack? Let’s ensure we adhere to industry best practices during implementation.
Feel free to ask questions for clarification or additional context.

### Assistant

I’d make this a **new project**, not an extension of Windowd.

The previous **Windowd** project was about managing a Claude Code/session window context. This project has a different scope, architecture, and potentially a standalone product identity. Sharing code concepts later is fine; sharing the repository/product identity would create unnecessary coupling.

One important update from checking the current market: there are already several tools specifically targeting arbitrary-window pinning, including AlwaysOnTop, Floaty, and On-Top. There is also an open-source approach called Topsy that uses ScreenCaptureKit to create a *mirror* of another window because macOS does not expose a public API for simply changing another process's window z-order. 

That actually makes the engineering question more interesting.

## 1. Name: my recommendation

I would **not** call it `Windowd`.

I'd also avoid generic names like `AlwaysOnTop`, `OnTop`, `Float`, or `PinTop`; those are already being used by existing Mac products. 

My preferred direction is:

### **Stay**

It communicates the core behavior beautifully:

> **Stay — Keep any window where you need it.**

It also leaves room for the product to evolve beyond simply "always on top."

Potential CLI/repository:

```text
Stay
stay-macos
stay-app
```

Other names I'd consider:

| Name | Feel | My take |
|---|---|---|
| **Stay** | Native, simple, memorable | ⭐ Best |
| Anchor | Technical, strong | Very good |
| Tether | Distinctive, slightly technical | Good |
| Hover | Visual, friendly | Good |
| LockWindow | Explicit | Too technical |
| Keep | Simple | Too generic |
| Latch | Nice metaphor | Good |
| Floatmark | Product-y | Less elegant |

I'd choose **Stay** unless trademark/App Store/domain research reveals a conflict.

---

# 2. But there's a more important architectural question

I want to revise our earlier assumption before we start implementation.

The phrase:

> "Make any existing macOS window always on top"

sounds straightforward, but **macOS's public APIs don't give us a general-purpose `setZOrder()` for another application's window**.

That's why some current implementations take fundamentally different approaches.

For example, Topsy explicitly uses **ScreenCaptureKit to mirror another application's window into a window owned by itself**, because the Window Server doesn't allow arbitrary applications to reorder another process's windows through public APIs. Its implementation is view-only because forwarding interaction back into the source window reliably isn't available through public APIs. 

That distinction is extremely important.

We therefore need to investigate two architectures:

### Architecture A — "Actually pin the original window"

```text
Finder window
     │
     ▼
Accessibility / Window APIs
     │
     ▼
Original Finder window
     │
     └── somehow stays above other windows
```

This would be ideal.

Advantages:

- Original window remains interactive.
- No screen capture.
- Minimal CPU/GPU overhead.
- Lowest memory usage.
- Potentially extremely elegant.

But we need to establish exactly what macOS permits for arbitrary third-party windows.

### Architecture B — "Create a floating mirror"

```text
Chrome
   │
   │ ScreenCaptureKit
   ▼
┌─────────────────┐
│   Stay Window   │  ← owned by us
│  live Chrome    │
└─────────────────┘
        ↑
      floating
```

This is much more controllable.

But:

- requires Screen Recording permission;
- consumes GPU/CPU resources;
- introduces capture latency;
- creates a second representation of the window;
- interaction is substantially harder;
- privacy implications are much more significant.

Topsy is an excellent example of this architecture in the current ecosystem. 

**For Stay, I would strongly prefer Architecture A and use B only as a deliberate fallback for functionality that genuinely cannot be achieved otherwise.**

---

# 3. Tech stack

I'd go fully native.

### Core

**Swift 6**

### UI

**SwiftUI + AppKit**

Not SwiftUI *instead of* AppKit.

I'd use:

```text
SwiftUI
   │
   ├── Preferences
   ├── onboarding
   ├── settings
   └── small UI surfaces
       
AppKit
   │
   ├── NSStatusItem
   ├── NSWindow
   ├── application lifecycle
   └── native macOS window behavior
```

Apple explicitly supports mixing AppKit and SwiftUI, and `NSStatusItem` is the native API for a menu-bar utility. 

That's a better fit than Electron/Tauri for this particular application because the interesting part of the application is **macOS system integration**, not rendering UI.

---

# 4. Native frameworks

I'd keep the dependency footprint very small.

```text
Swift
├── SwiftUI
├── AppKit
├── ApplicationServices
├── CoreGraphics
└── Carbon
```

Possibly:

```text
os.log
```

for structured logging.

### Accessibility

`ApplicationServices` / `AXUIElement`

Apple describes AXUIElement as the mechanism through which assistive applications communicate with and control accessible applications. Accessibility objects can expose hierarchy, screen position, attributes, actions, and state notifications. 

That should be our primary abstraction around third-party windows.

### Window discovery

Core Graphics where appropriate.

We should be careful not to continuously enumerate the entire window list. The app should react to events and query state only when required.

### Menu bar

`NSStatusItem`.

Apple's API is explicitly designed for system menu-bar items. 

---

# 5. Architecture I'd use

I'd make this a proper layered system from day one:

```text
┌─────────────────────────────────────────────┐
│                 Stay App                    │
├─────────────────────────────────────────────┤
│ Presentation                                │
│   SwiftUI / Menu Bar / Preferences          │
├─────────────────────────────────────────────┤
│ Application                                │
│   PinWindow                                 │
│   UnpinWindow                               │
│   TogglePinnedWindow                        │
│   SelectWindow                              │
├─────────────────────────────────────────────┤
│ Domain                                     │
│   Window                                    │
│   Application                               │
│   WindowIdentifier                          │
│   PinState                                  │
├─────────────────────────────────────────────┤
│ Infrastructure                             │
│   AccessibilityWindowProvider               │
│   WindowDiscovery                           │
│   HotkeyManager                             │
│   PermissionManager                         │
│   Persistence                               │
├─────────────────────────────────────────────┤
│ macOS                                      │
│   AppKit                                    │
│   AXUIElement                               │
│   CoreGraphics                              │
└─────────────────────────────────────────────┘
```

The important principle:

> **Business logic should not know that `AXUIElement` exists.**

It should deal with:

```swift
protocol WindowController {
    func pin(_ window: Window) async throws
    func unpin(_ window: Window) async throws
}
```

Then macOS-specific code implements that.

This makes the project dramatically easier to test and evolve.

---

# 6. Project structure

I'd start with something like:

```text
Stay/
├── StayApp/
│   ├── StayApp.swift
│   ├── AppDelegate.swift
│   └── MenuBar/
│
├── Domain/
│   ├── Window.swift
│   ├── WindowID.swift
│   ├── Application.swift
│   └── PinState.swift
│
├── Application/
│   ├── TogglePinUseCase.swift
│   ├── PinWindowUseCase.swift
│   └── WindowSelectionUseCase.swift
│
├── Infrastructure/
│   ├── Accessibility/
│   ├── Windows/
│   ├── Hotkeys/
│   ├── Permissions/
│   ├── Persistence/
│   └── Logging/
│
├── Presentation/
│   ├── MenuBar/
│   ├── Settings/
│   └── Onboarding/
│
├── Tests/
│   ├── DomainTests/
│   ├── ApplicationTests/
│   └── InfrastructureTests/
│
└── Stay.xcodeproj
```

That's deliberately more structured than necessary for v0.

That's intentional.

We're treating this as a **real macOS application**, not a throwaway script.

---

# 7. What I would *not* use

### Electron

No.

It would add a browser runtime to an application whose core purpose is talking to macOS's window system.

### Tauri

Much more reasonable than Electron, but still not my first choice.

Tauri is attractive for lightweight applications and there are current window utilities using it, but we'd still end up writing substantial native macOS integration. 

For this project, going directly to Swift/AppKit gives us the cleanest access to the system.

### Python

Definitely not for the production application.

Fine for experiments, scripts, or reverse-engineering behavior.

### Third-party window-management frameworks

Initially: **none**.

I'd rather understand Apple's APIs directly than build our core functionality on top of another abstraction.

---

# 8. Permissions philosophy

This is especially important for Stay.

I'd aim for:

```text
Network permission       ❌
Screen Recording         ❌ initially
Input Monitoring         ❌ initially
Accessibility            ✅ if required
```

And:

```text
No account
No cloud
No telemetry by default
No remote server
No window contents uploaded
```

Apple explicitly emphasizes informed consent and minimizing access to user/device data, while App Sandbox restricts access to protected resources. 

That gives us a strong product philosophy:

> **Stay runs entirely on your Mac.**

---

# 9. Battery/memory target

I'd actually make this a project requirement.

Something like:

```text
IDLE TARGET

CPU:       ≈ 0% sustained
Memory:    < 30 MB
Network:   0
GPU:       0 while idle
Wakeups:   minimal
```

Those aren't promises yet; they're **engineering targets** that we'll measure rather than assume.

And I'd add performance tests/profiling to the development process rather than checking Activity Monitor once at the end.

For a menu-bar utility, there is no reason for the app to be doing meaningful work continuously.

---

# 10. One change to our MVP

I would **not** begin with:

> "Build Always on Top."

I'd begin with:

### **Phase 0 — Window Capability Research**

Build a tiny diagnostic application that can answer:

```text
What is the currently focused window?
What application owns it?
What is its AX role?
What is its PID?
What is its CGWindowID?
Can we identify it consistently?
Can we observe when it changes?
What operations does macOS expose for it?
```

Test against:

```text
Finder
Safari
Chrome
Firefox
Terminal
iTerm2
VS Code
WhatsApp
Slack
Discord
Spotify
IINA
VLC
Preview
System Settings
```

Then specifically investigate:

```text
Can we change stacking order?
Can we make an arbitrary external window floating?
Can we keep it above another application's normal window?
Can we keep it across Spaces?
What happens with fullscreen?
What happens when the application recreates the window?
```

**Only after those results are known should we lock the production architecture.**

That is the industry-practice approach I'd recommend: validate the riskiest technical assumption first.

---

# 11. So the decision I'd make today

| Decision | Recommendation |
|---|---|
| Project | **New project** |
| Product name | **Stay** |
| Repository | `stay-macos` |
| Language | **Swift 6** |
| UI | **SwiftUI + AppKit** |
| Window integration | **Accessibility + Core Graphics** |
| Global shortcut | Native macOS mechanism |
| Architecture | Layered / protocol-driven |
| External dependencies | Minimal / preferably zero |
| Persistence | Local |
| Cloud | None |
| Analytics | None initially |
| Screen Recording | Avoid unless technically necessary |
| Electron | No |
| Tauri | No initially |
| Python | Prototype only |
| First milestone | **Prove arbitrary-window pinning is actually possible with public APIs** |

And I would keep **Windowd completely separate**. Later, they could share a small internal macOS utility library if we actually discover reusable code, but there should be no conceptual coupling between the products.

The most important next step is therefore **not Xcode scaffolding**. It's a small technical spike around the macOS Window Server/Accessibility APIs. That determines whether Stay can deliver the experience we actually want — *the original Finder/Chrome/WhatsApp/etc. window staying interactive and genuinely on top* — without resorting to ScreenCaptureKit mirroring. The existence of Topsy's mirror-based architecture is a strong signal that we should validate this assumption very carefully first. 

