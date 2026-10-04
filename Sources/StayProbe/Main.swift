import Foundation
import AppKit
import CoreGraphics

@main
struct StayProbeMain {
    static func main() async {
        let args = CommandLine.arguments
        
        // Non-interactive flags
        if args.contains("--list") {
            enumerateWindows()
            return
        }
        
        if let idx = args.firstIndex(of: "--test-wid"), idx + 1 < args.count, let widVal = UInt32(args[idx + 1]) {
            await runAutomatedWidTest(wid: widVal)
            return
        }
        
        if let idx = args.firstIndex(of: "--inspect-pid"), idx + 1 < args.count, let pidVal = Int32(args[idx + 1]) {
            runInspectPid(pid: pidVal)
            return
        }

        // Phase 0.5 spike probes
        if let idx = args.firstIndex(of: "--probe-raise"), idx + 1 < args.count, let widVal = UInt32(args[idx + 1]) {
            requireAccessibility()
            RaiseProbeService.shared.probeRaise(wid: widVal, auto: args.contains("--auto"))
            return
        }

        if let idx = args.firstIndex(of: "--probe-watch"), idx + 1 < args.count, let widVal = UInt32(args[idx + 1]) {
            requireAccessibility()
            let duration = flagValue(args, "--duration").flatMap(Double.init) ?? 60
            let policy = flagValue(args, "--policy").flatMap(RaisePolicy.init(rawValue:)) ?? .events
            RaiseProbeService.shared.probeWatch(wid: widVal, duration: duration, policy: policy)
            return
        }

        if let idx = args.firstIndex(of: "--probe-flash"), idx + 1 < args.count, let widVal = UInt32(args[idx + 1]) {
            requireAccessibility()
            RaiseProbeService.shared.probeFlash(wid: widVal)
            return
        }

        if let idx = args.firstIndex(of: "--probe-sls"), idx + 1 < args.count, let widVal = UInt32(args[idx + 1]) {
            SkyLightProbeService.shared.run(wid: widVal)
            return
        }
        
        printHeader()
        
        let permissions = PermissionService.shared
        if !permissions.isAccessibilityGranted {
            print("⚠️  Accessibility permission is NOT currently granted for this process/terminal.")
            print("👉 Prompting for permission now. Please check macOS System Settings > Privacy & Security > Accessibility.")
            permissions.promptForAccessibility()
            print("Press Enter once granted, or press Enter to continue anyway...")
            _ = readLine()
        } else {
            print("✅ Accessibility Permission: GRANTED")
        }
        
        let control = WindowControlService.shared
        if control.isSkyLightAvailable {
            print("✅ SkyLight WindowServer Bridge: AVAILABLE")
        } else {
            print("⚠️  SkyLight WindowServer Bridge: UNAVAILABLE")
        }
        
        print("\n" + String(repeating: "=", count: 60) + "\n")
        
        while true {
            printMenu()
            guard let choice = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                continue
            }
            
            switch choice {
            case "1":
                await inspectActiveWindow()
            case "2":
                await pinActiveWindow()
            case "3":
                await unpinActiveWindow()
            case "4":
                await runLiveMonitor()
            case "5":
                enumerateWindows()
            case "6":
                await auditAXAttributes()
            case "q", "exit":
                cleanupAndExit()
                return
            default:
                print("Unknown option. Please choose 1-6 or 'q'.")
            }
        }
    }
    
    private static func flagValue(_ args: [String], _ flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static func requireAccessibility() {
        guard !PermissionService.shared.isAccessibilityGranted else { return }
        print("⚠️  Accessibility permission is NOT granted for this process.")
        print("👉 Grant it to your terminal in System Settings > Privacy & Security > Accessibility,")
        print("   then re-run. Probe results are meaningless without it.")
        PermissionService.shared.promptForAccessibility()
    }

    private static func printHeader() {
        print("""
        ============================================================
           STAY PROBE — Phase 0 macOS Window Capability Diagnostic
        ============================================================
        OS: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Process PID: \(ProcessInfo.processInfo.processIdentifier)
        """)
    }
    
    private static func printMenu() {
        print("""
        
        Select an action:
          [1] 🔍 Inspect Active Window (3s countdown to switch to target)
          [2] 📌 Pin Active Window to Floating (Always on Top)
          [3] 📍 Unpin Active Window (Restore normal level)
          [4] 📡 Live Window Monitor (Stream focus transitions)
          [5] 🪟 List All On-Screen Windows
          [6] 🔬 Deep AX Attributes & Settability Audit
          [q] ❌ Quit (Restores any pinned windows)
        
        Enter choice: 
        """, terminator: "")
    }
    
    private static func countdown(seconds: Int, prompt: String) async {
        print("\n\(prompt)")
        for s in (1...seconds).reversed() {
            print("  Switch to target app... \(s)s", terminator: "\r")
            fflush(stdout)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        print("  Capturing target window now!            \n")
    }
    
    private static func inspectActiveWindow() async {
        await countdown(seconds: 3, prompt: "👉 Switch to the window you want to inspect.")
        
        let discovery = WindowDiscoveryService.shared
        guard let frontApp = discovery.getFrontmostApp() else {
            print("❌ Failed to detect frontmost application.")
            return
        }
        
        print("Application:")
        print("  Name:     \(frontApp.name)")
        print("  PID:      \(frontApp.pid)")
        print("  Bundle:   \(frontApp.bundleIdentifier ?? "(none)")")
        
        guard let (window, _) = discovery.getFocusedWindow(for: frontApp.pid) else {
            print("❌ Failed to resolve focused window via Accessibility API.")
            print("   Possible reasons: app has no open windows, or Accessibility permission not trusted.")
            return
        }
        
        print("\nFocused Window:")
        print("  Title:        \"\(window.title)\"")
        print("  Role:         \(window.role) \(window.subrole.map { "(\($0))" } ?? "")")
        if let wid = window.windowID {
            print("  CGWindowID:   \(wid)")
            if let level = WindowControlService.shared.getWindowLevel(windowID: wid) {
                print("  Window Level: \(level)")
            }
        } else {
            print("  CGWindowID:   ⚠️  Could not resolve CGWindowID")
        }
        
        if let frame = window.frame {
            print("  Frame:        origin=(\(Int(frame.origin.x)), \(Int(frame.origin.y))), size=(\(Int(frame.size.width))x\(Int(frame.size.height)))")
        }
        print("  Is Minimized: \(window.isMinimized)")
        print("  Is Main:      \(window.isMainWindow)")
        print("  Actions (\(window.supportedActions.count)):    \(window.supportedActions.joined(separator: ", "))")
    }
    
    private static func pinActiveWindow() async {
        await countdown(seconds: 3, prompt: "👉 Switch to the window you want to PIN to Always on Top.")
        
        let discovery = WindowDiscoveryService.shared
        guard let frontApp = discovery.getFrontmostApp(),
              let (window, _) = discovery.getFocusedWindow(for: frontApp.pid) else {
            print("❌ Could not get focused window.")
            return
        }
        
        guard let wid = window.windowID else {
            print("❌ Cannot pin window: CGWindowID could not be resolved.")
            return
        }
        
        print("Target: [\(frontApp.name)] \"\(window.title)\" (CGWindowID: \(wid))")
        let currentLevel = WindowControlService.shared.getWindowLevel(windowID: wid) ?? 0
        print("Current Window Level: \(currentLevel)")
        
        let control = WindowControlService.shared
        let result = control.pinToFloating(windowID: wid, preset: .floating)
        
        if result.success {
            let newLevel = control.getWindowLevel(windowID: wid) ?? -1
            print("🎉 SUCCESS: Window pinned to Floating Level!")
            print("   Previous Level: \(currentLevel) -> New Level: \(newLevel)")
            print("👉 Now try clicking on other windows or background apps. The pinned window should stay on top!")
        } else {
            print("❌ FAILED to pin window: \(result.error ?? "Unknown error")")
        }
    }
    
    private static func unpinActiveWindow() async {
        await countdown(seconds: 3, prompt: "👉 Switch to the window you want to UNPIN.")
        
        let discovery = WindowDiscoveryService.shared
        guard let frontApp = discovery.getFrontmostApp(),
              let (window, _) = discovery.getFocusedWindow(for: frontApp.pid) else {
            print("❌ Could not get focused window.")
            return
        }
        
        guard let wid = window.windowID else {
            print("❌ Cannot unpin window: CGWindowID could not be resolved.")
            return
        }
        
        print("Target: [\(frontApp.name)] \"\(window.title)\" (CGWindowID: \(wid))")
        let control = WindowControlService.shared
        let result = control.unpin(windowID: wid)
        
        if result.success {
            let newLevel = control.getWindowLevel(windowID: wid) ?? -1
            print("✅ SUCCESS: Window unpinned. Current Level: \(newLevel)")
        } else {
            print("❌ FAILED to unpin window: \(result.error ?? "Unknown error")")
        }
    }
    
    private static func runLiveMonitor() async {
        print("\n📡 Starting Live Monitor. Focus different windows to see events.")
        print("Press Enter to stop monitoring...\n")
        
        let discovery = WindowDiscoveryService.shared
        let control = WindowControlService.shared
        
        let monitorTask = Task {
            var lastPID: pid_t = 0
            var lastTitle = ""
            
            while !Task.isCancelled {
                if let front = discovery.getFrontmostApp() {
                    if let (window, _) = discovery.getFocusedWindow(for: front.pid) {
                        if front.pid != lastPID || window.title != lastTitle {
                            lastPID = front.pid
                            lastTitle = window.title
                            let widStr = window.windowID.map { "wid: \($0)" } ?? "wid: ?"
                            let levelStr: String
                            if let wid = window.windowID, let lvl = control.getWindowLevel(windowID: wid) {
                                let pinnedMarker = control.isPinned(windowID: wid) ? " [PINNED]" : ""
                                levelStr = "level: \(lvl)\(pinnedMarker)"
                            } else {
                                levelStr = "level: ?"
                            }
                            print("🔔 [\(front.name)] \"\(window.title)\" | \(widStr) | \(levelStr)")
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms sample
            }
        }
        
        _ = readLine()
        monitorTask.cancel()
        print("Stopped monitor.")
    }
    
    private static func enumerateWindows() {
        print("\n🪟 Enumerating on-screen windows (CGWindowListCopyWindowInfo):")
        let windows = WindowDiscoveryService.shared.getAllOnScreenWindows()
        print(String(format: "%-8@ %-8@ %-6@ %-25@ %@", "WID", "PID", "Layer", "Owner App", "Window Title"))
        print(String(repeating: "-", count: 80))
        
        for w in windows {
            let wid = w[kCGWindowNumber as String] as? NSNumber ?? 0
            let pid = w[kCGWindowOwnerPID as String] as? NSNumber ?? 0
            let layer = w[kCGWindowLayer as String] as? NSNumber ?? 0
            let owner = w[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let name = w[kCGWindowName as String] as? String ?? "(no title)"
            
            // Filter out internal system layers (e.g. wallpaper, cursor, menu bar backing)
            let ownerTrunc = String(owner.prefix(24))
            let nameTrunc = String(name.prefix(35))
            print(String(format: "%-8d %-8d %-6d %-25@ %@", wid.intValue, pid.intValue, layer.intValue, ownerTrunc, nameTrunc))
        }
    }
    
    private static func auditAXAttributes() async {
        await countdown(seconds: 3, prompt: "👉 Switch to the window to audit AX attributes.")
        
        let discovery = WindowDiscoveryService.shared
        guard let frontApp = discovery.getFrontmostApp(),
              let (window, element) = discovery.getFocusedWindow(for: frontApp.pid) else {
            print("❌ Could not get focused window.")
            return
        }
        
        print("\n🔬 AX Attributes Audit for [\(frontApp.name)] \"\(window.title)\":")
        let settableMap = WindowControlService.shared.checkSettableAttributes(element: element)
        
        print("\n  Settable Attributes (\(settableMap.filter { $0.value }.count)):")
        for (attr, isSettable) in settableMap.sorted(by: { $0.key < $1.key }) where isSettable {
            print("    ✅ \(attr)")
        }
        
        print("\n  Read-Only Attributes (\(settableMap.filter { !$0.value }.count)):")
        for (attr, isSettable) in settableMap.sorted(by: { $0.key < $1.key }) where !isSettable {
            print("    🔒 \(attr)")
        }
        
        print("\n  Supported Actions:")
        for action in window.supportedActions {
            print("    ⚡️ \(action)")
        }
    }
    
    private static func runAutomatedWidTest(wid: CGWindowID) async {
        let control = WindowControlService.shared
        print("🧪 Running automated window level test on CGWindowID: \(wid)")
        guard control.isSkyLightAvailable else {
            print("❌ SkyLight bridge is unavailable.")
            return
        }
        
        let initialLevel = control.getWindowLevel(windowID: wid) ?? 0
        print("  1. Initial level: \(initialLevel)")
        
        print("  2. Setting window to Floating (level 3)...")
        let pinResult = control.pinToFloating(windowID: wid, preset: .floating)
        guard pinResult.success else {
            print("  ❌ Pin failed: \(pinResult.error ?? "unknown")")
            return
        }
        
        let pinnedLevel = control.getWindowLevel(windowID: wid) ?? -1
        print("  3. Readback pinned level: \(pinnedLevel)")
        
        if pinnedLevel == WindowLevelPreset.floating.rawValue {
            print("  ✅ VERIFIED: Window level updated to floating (3) successfully!")
        } else {
            print("  ⚠️  Window level is \(pinnedLevel), expected \(WindowLevelPreset.floating.rawValue)")
        }
        
        print("  4. Restoring window to original level (\(initialLevel))...")
        let unpinResult = control.unpin(windowID: wid)
        let restoredLevel = control.getWindowLevel(windowID: wid) ?? -1
        print("  5. Readback restored level: \(restoredLevel)")
        
        if unpinResult.success && restoredLevel == initialLevel {
            print("  ✅ VERIFIED: Window successfully restored to original level!")
        } else {
            print("  ⚠️  Unpin verification issue: level is \(restoredLevel), expected \(initialLevel)")
        }
    }
    
    private static func runInspectPid(pid: pid_t) {
        let discovery = WindowDiscoveryService.shared
        guard let (window, _) = discovery.getFocusedWindow(for: pid) else {
            print("❌ No focused window found for PID \(pid)")
            return
        }
        print("Inspecting PID \(pid):")
        print("  App:        \(window.app.name)")
        print("  Title:      \"\(window.title)\"")
        print("  Role:       \(window.role)")
        print("  CGWindowID: \(window.windowID.map { String($0) } ?? "None")")
        if let wid = window.windowID, let lvl = WindowControlService.shared.getWindowLevel(windowID: wid) {
            print("  Level:      \(lvl)")
        }
    }
    
    private static func cleanupAndExit() {
        let control = WindowControlService.shared
        let pinned = control.pinnedWindowIDs
        if !pinned.isEmpty {
            print("\n🧹 Restoring \(pinned.count) pinned window(s) to normal level before exiting...")
            for wid in pinned {
                _ = control.unpin(windowID: wid)
            }
            print("✅ All windows restored.")
        }
        print("Goodbye!")
    }
}
