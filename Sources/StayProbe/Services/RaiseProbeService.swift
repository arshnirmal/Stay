import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// How the watch probe reacts when the target window gets buried.
public enum RaisePolicy: String, Sendable {
    /// Never re-raise. Pure measurement of how often burial happens.
    case observe
    /// Re-raise only from AX / NSWorkspace notifications — the candidate architecture.
    case events
    /// Re-raise from the z-order sampler — the watchdog fallback.
    case poll
}

/// C callback for AXObserver. Must be a free function to be @convention(c).
private func axProbeCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    RaiseProbeService.shared.record(event: notification as String, pid: pid)
}

/// Probes A and B — does `kAXRaiseAction` actually work on foreign windows,
/// and can notifications alone keep a window on top?
public final class RaiseProbeService: NSObject, @unchecked Sendable {
    public static let shared = RaiseProbeService()

    private static let watchedNotifications: [String] = [
        kAXApplicationActivatedNotification as String,
        kAXWindowCreatedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXMainWindowChangedNotification as String,
        kAXApplicationShownNotification as String,
        kAXWindowMiniaturizedNotification as String,
    ]

    private struct Burial {
        let at: Date
        let occluder: String
        let coverage: Double
        var attributedTo: String?
        var restoredAfter: TimeInterval?
    }

    private var observers: [pid_t: AXObserver] = [:]
    private var eventLog: [(at: Date, name: String, app: String)] = []
    private var burials: [Burial] = []
    private var pending: Burial?
    private var wasOccluded = false
    private var raiseCount = 0
    private var focusSteals = 0

    private var targetWID: CGWindowID = 0
    private var targetElement: AXUIElement?
    private var policy: RaisePolicy = .events
    private var sampler: Timer?

    private override init() { super.init() }

    // MARK: - Probe A: does AXRaise beat the frontmost app, without stealing focus?

    public func probeRaise(wid: CGWindowID, countdownSeconds: Int = 6, auto: Bool = false) {
        print("\n🔬 PROBE A — kAXRaiseAction against the frontmost app")
        print(String(repeating: "─", count: 72))

        guard let (_, target) = ZOrderService.find(wid, in: ZOrderService.snapshot()) else {
            print("  ❌ CGWindowID \(wid) is not an on-screen normal window. Run --list first.")
            return
        }
        guard let element = ZOrderService.axElement(for: wid, pid: target.pid) else {
            print("  ❌ Could not resolve an AX element for wid \(wid) (pid \(target.pid)).")
            print("     Accessibility permission may not be granted to this terminal.")
            return
        }

        print("  Target: [\(target.owner)] \"\(target.title)\" wid=\(wid) pid=\(target.pid)")

        if auto {
            guard let burier = pickBurier(for: target) else {
                print("  ❌ No other app has a window overlapping the target; cannot bury it automatically.")
                return
            }
            print("  Burier: [\(burier.owner)] wid=\(burier.wid) pid=\(burier.pid) — activating it now.")
            NSRunningApplication(processIdentifier: burier.pid)?.activate()
            Thread.sleep(forTimeInterval: 1.2)
        } else {
            print("\n  👉 Now click a DIFFERENT app whose window OVERLAPS the target,")
            print("     so the target is visibly buried. Do not touch anything after that.")
            for s in (1...countdownSeconds).reversed() {
                print("     measuring in \(s)s ...", terminator: "\r")
                fflush(stdout)
                Thread.sleep(forTimeInterval: 1)
            }
            print("     measuring now.                    ")
        }

        let beforeSnap = ZOrderService.snapshot()
        let beforeRank = ZOrderService.find(wid, in: beforeSnap)?.index
        let beforeCover = ZOrderService.occludedFraction(of: wid, in: beforeSnap)
        let beforeFront = NSWorkspace.shared.frontmostApplication

        print("\n  BEFORE  z-rank=\(beforeRank.map(String.init) ?? "?")  "
              + "occluded=\(pct(beforeCover))  frontmost=\(beforeFront?.localizedName ?? "?")")

        if beforeCover < 0.02 {
            print("  ⚠️  Target was not actually buried — result will not be meaningful.")
        }

        let clock = Date()
        let err = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let callDuration = Date().timeIntervalSince(clock)
        Thread.sleep(forTimeInterval: 0.25)

        let afterSnap = ZOrderService.snapshot()
        let afterRank = ZOrderService.find(wid, in: afterSnap)?.index
        let afterCover = ZOrderService.occludedFraction(of: wid, in: afterSnap)
        let afterFront = NSWorkspace.shared.frontmostApplication

        print("  AFTER   z-rank=\(afterRank.map(String.init) ?? "?")  "
              + "occluded=\(pct(afterCover))  frontmost=\(afterFront?.localizedName ?? "?")")

        // Does it hold with no further input?
        Thread.sleep(forTimeInterval: 3.0)
        let holdCover = ZOrderService.occludedFraction(of: wid, in: ZOrderService.snapshot())

        print("\n  RESULTS")
        print("    AXRaiseAction return ........ \(err == .success ? "success" : "AXError \(err.rawValue)")")
        print("    Call duration ............... \(String(format: "%.1f ms", callDuration * 1000))")
        line("Raised above frontmost app", afterCover < 0.02 && beforeCover >= 0.02)
        line("Focus NOT stolen", afterFront?.processIdentifier == beforeFront?.processIdentifier)
        line("Still on top after 3s idle", holdCover < 0.02)

        print("\n  VERDICT: ", terminator: "")
        if afterCover < 0.02 && afterFront?.processIdentifier == beforeFront?.processIdentifier {
            print("✅ Event-driven AX raise is VIABLE.")
        } else if afterCover < 0.02 {
            print("⚠️  Raise works but STEALS FOCUS — architecture needs rework.")
        } else {
            print("❌ AXRaiseAction cannot beat the frontmost app. Native path is DEAD.")
        }
        print(String(repeating: "─", count: 72))
    }

    // MARK: - Probe A2: does "activate, then hand focus back" leave it on top?

    /// The last unprivileged trick: app activation DOES put a window at rank 0.
    /// This measures whether that survives returning focus to the other app.
    public func probeFlash(wid: CGWindowID) {
        print("\n🔬 PROBE A2 — activate target, then return focus to the other app")
        print(String(repeating: "─", count: 72))

        guard let (_, target) = ZOrderService.find(wid, in: ZOrderService.snapshot()),
              let element = ZOrderService.axElement(for: wid, pid: target.pid),
              let burier = pickBurier(for: target) else {
            print("  ❌ Could not set up target/burier pair.")
            return
        }
        let targetApp = NSRunningApplication(processIdentifier: target.pid)
        let burierApp = NSRunningApplication(processIdentifier: burier.pid)

        print("  Target: [\(target.owner)] wid=\(wid)   Burier: [\(burier.owner)] wid=\(burier.wid)\n")

        func step(_ label: String) {
            let snap = ZOrderService.snapshot()
            let rank = ZOrderService.find(wid, in: snap)?.index
            let cover = ZOrderService.occludedFraction(of: wid, in: snap)
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            print("    \(label.padding(toLength: 34, withPad: ".", startingAt: 0)) "
                  + "z-rank=\(rank.map(String.init) ?? "?")  occluded=\(pct(cover))  front=\(front)")
        }

        burierApp?.activate(); Thread.sleep(forTimeInterval: 1.0)
        step("1. burier activated")

        targetApp?.activate(); Thread.sleep(forTimeInterval: 0.8)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        Thread.sleep(forTimeInterval: 0.4)
        step("2. target activated + raised")

        burierApp?.activate(); Thread.sleep(forTimeInterval: 1.0)
        step("3. focus handed back to burier")

        Thread.sleep(forTimeInterval: 2.0)
        let finalCover = ZOrderService.occludedFraction(of: wid, in: ZOrderService.snapshot())
        step("4. after 2s settle")

        print("\n  VERDICT: ", terminator: "")
        if finalCover < 0.02 {
            print("✅ Window SURVIVES focus handback — flash-activate is viable.")
        } else {
            print("❌ Window drops back the instant focus returns. Trick is dead.")
        }
        print(String(repeating: "─", count: 72))
    }

    /// Picks another app's window that overlaps the target, to bury it with.
    private func pickBurier(for target: ZWindow) -> ZWindow? {
        ZOrderService.snapshot().first {
            $0.pid != target.pid
                && $0.bounds.intersects(target.bounds)
                && $0.bounds.width > 200 && $0.bounds.height > 200
                && NSRunningApplication(processIdentifier: $0.pid)?.activationPolicy == .regular
        }
    }

    // MARK: - Probe B: can notifications alone keep it on top?

    public func probeWatch(wid: CGWindowID, duration: TimeInterval, policy: RaisePolicy) {
        print("\n🔬 PROBE B — event coverage & re-raise latency (policy: \(policy.rawValue))")
        print(String(repeating: "─", count: 72))

        guard let (_, target) = ZOrderService.find(wid, in: ZOrderService.snapshot()) else {
            print("  ❌ CGWindowID \(wid) is not an on-screen normal window.")
            return
        }
        guard let element = ZOrderService.axElement(for: wid, pid: target.pid) else {
            print("  ❌ Could not resolve an AX element for wid \(wid).")
            return
        }

        targetWID = wid
        targetElement = element
        self.policy = policy
        eventLog = []; burials = []; pending = nil
        wasOccluded = false; raiseCount = 0; focusSteals = 0

        installWorkspaceObservers()
        installAXObservers()

        print("  Target: [\(target.owner)] \"\(target.title)\" wid=\(wid)")
        print("  Watching \(observers.count) apps for \(Self.watchedNotifications.count) notification types.")
        print("\n  👉 Use your Mac normally for \(Int(duration))s — switch apps, open windows,")
        print("     trigger Spotlight, open a sheet. Try hard to bury the target.\n")

        sampler = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.sample()
        }

        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.2, false)
            let left = Int(deadline.timeIntervalSinceNow)
            print("  ⏱  \(left)s left | burials=\(burials.count + (pending != nil ? 1 : 0)) "
                  + "raises=\(raiseCount) events=\(eventLog.count)   ", terminator: "\r")
            fflush(stdout)
        }

        sampler?.invalidate(); sampler = nil
        teardownObservers()
        print("\n")
        report()
    }

    private func sample() {
        let snap = ZOrderService.snapshot()
        let coverage = ZOrderService.occludedFraction(of: targetWID, in: snap)
        let occluded = coverage > 0.02

        if occluded && !wasOccluded {
            let top = ZOrderService.occluders(of: targetWID, in: snap).first
            var burial = Burial(
                at: Date(),
                occluder: top.map { "\($0.owner)" } ?? "?",
                coverage: coverage
            )
            burial.attributedTo = attributeRecentEvent(before: burial.at)
            pending = burial
            if policy == .poll { performRaise(reason: "sampler") }
        }

        if !occluded && wasOccluded, var burial = pending {
            burial.restoredAfter = Date().timeIntervalSince(burial.at)
            burials.append(burial)
            pending = nil
        }

        wasOccluded = occluded
    }

    /// Was there a notification just before this burial that the architecture could key off?
    private func attributeRecentEvent(before instant: Date) -> String? {
        eventLog.last(where: { instant.timeIntervalSince($0.at) < 0.30 && $0.at <= instant })
            .map { "\($0.name.replacingOccurrences(of: "AX", with: "")) (\($0.app))" }
    }

    fileprivate func record(event name: String, pid: pid_t) {
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        eventLog.append((at: Date(), name: name, app: app))
        if policy == .events { performRaise(reason: name) }
    }

    private func performRaise(reason: String) {
        guard let targetElement else { return }
        let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        AXUIElementPerformAction(targetElement, kAXRaiseAction as CFString)
        raiseCount += 1
        let frontAfter = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if frontBefore != frontAfter { focusSteals += 1 }
    }

    // MARK: - Observers

    private func installWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(workspaceDidActivate(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(workspaceDidLaunch(_:)),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    }

    @objc private func workspaceDidActivate(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        record(event: "NSWorkspaceDidActivate", pid: app?.processIdentifier ?? 0)
    }

    @objc private func workspaceDidLaunch(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        install(pid: app.processIdentifier)
    }

    private func installAXObservers() {
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard app.processIdentifier != me else { continue }
            install(pid: app.processIdentifier)
        }
    }

    private func install(pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, axProbeCallback, &observer) == .success, let observer else { return }
        let appElement = AXUIElementCreateApplication(pid)
        for name in Self.watchedNotifications {
            AXObserverAddNotification(observer, appElement, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func teardownObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for (_, observer) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
    }

    // MARK: - Report

    private func report() {
        if let pending { burials.append(pending); self.pending = nil }

        print("📊 PROBE B RESULTS")
        print(String(repeating: "─", count: 72))
        print("  Burials observed ............ \(burials.count)")
        print("  Raises performed ............ \(raiseCount)")
        print("  Focus steals ................ \(focusSteals)")
        print("  Notifications received ...... \(eventLog.count)")

        let attributed = burials.filter { $0.attributedTo != nil }
        let blind = burials.filter { $0.attributedTo == nil }
        print("\n  EVENT COVERAGE  (can notifications see every burial?)")
        print("    Burials preceded by an event ... \(attributed.count)/\(burials.count)")
        print("    ⚠️  BLIND SPOTS (no event) ....... \(blind.count)/\(burials.count)")

        if !blind.isEmpty {
            print("\n    Blind-spot occluders:")
            for (occluder, count) in tally(blind.map(\.occluder)) {
                print("      • \(occluder) — \(count)×")
            }
        }

        let restored = burials.compactMap(\.restoredAfter).sorted()
        print("\n  RECOVERY LATENCY  (burial → back on top)")
        if restored.isEmpty {
            print("    No burial was ever recovered.")
        } else {
            print("    recovered ..... \(restored.count)/\(burials.count)")
            print("    median ........ \(String(format: "%.0f ms", restored[restored.count / 2] * 1000))")
            print("    p90 ........... \(String(format: "%.0f ms", restored[min(restored.count - 1, Int(Double(restored.count) * 0.9))] * 1000))")
            print("    max ........... \(String(format: "%.0f ms", (restored.last ?? 0) * 1000))")
        }
        let unrecovered = burials.count - restored.count
        if unrecovered > 0 {
            print("    ❌ never recovered ... \(unrecovered)")
        }

        print("\n  NOTIFICATION MIX")
        for (name, count) in tally(eventLog.map(\.name)) {
            let wasted = policy == .events && burials.isEmpty
            print("    \(name.padding(toLength: 42, withPad: " ", startingAt: 0)) \(count)×"
                  + (wasted ? "  (all wasted)" : ""))
        }
        if policy == .events && raiseCount > 0 {
            let efficiency = Double(burials.count) / Double(raiseCount)
            print("\n  Raise efficiency (burials/raises) ... \(String(format: "%.1f%%", efficiency * 100))")
            print("  → low efficiency means the event set is noisy and needs narrowing.")
        }
        print(String(repeating: "─", count: 72))
    }

    // MARK: - Formatting helpers

    private func tally(_ values: [String]) -> [(String, Int)] {
        Dictionary(grouping: values, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    private func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    private func line(_ label: String, _ pass: Bool) {
        let padded = label.padding(toLength: 28, withPad: ".", startingAt: 0)
        print("    \(padded) \(pass ? "✅ YES" : "❌ NO")")
    }
}
