import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

public final class WindowDiscoveryService: @unchecked Sendable {
    public static let shared = WindowDiscoveryService()

    private let excludedOwners: Set<String> = [
        "Stay",
        "Window Server",
        "Dock",
        "Notification Centre",
        "Notification Center",
        "WindowManager",
        "Control Center",
        "Spotlight",
        "SystemUIServer"
    ]

    private let lock = NSLock()
    private var _lastNonStayApp: NSRunningApplication?

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // Initialize with current frontmost app if not Stay
        if let current = NSWorkspace.shared.frontmostApplication,
           current.bundleIdentifier != Bundle.main.bundleIdentifier {
            _lastNonStayApp = current
        }
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        if app.bundleIdentifier != Bundle.main.bundleIdentifier && app.activationPolicy == .regular {
            lock.withLock {
                _lastNonStayApp = app
            }
        }
    }

    public func isEligible(owner: String, role: String, bounds: CGRect) -> Bool {
        if excludedOwners.contains(owner) { return false }
        if bounds.width < 100 || bounds.height < 100 { return false }
        if role != "AXWindow" && role != "AXFloatingWindow" { return false }
        return true
    }

    public func getFrontmostTargetWindow() -> TargetWindow? {
        var frontApp = NSWorkspace.shared.frontmostApplication
        let stayBundleID = Bundle.main.bundleIdentifier ?? "com.arsh.stay"

        if frontApp?.bundleIdentifier == stayBundleID || frontApp == nil {
            frontApp = lock.withLock { _lastNonStayApp }
                ?? NSWorkspace.shared.runningApplications.first(where: {
                    $0.activationPolicy == .regular && $0.bundleIdentifier != stayBundleID && !$0.isHidden
                })
        }

        guard let targetApp = frontApp else {
            NSLog("[Stay] getFrontmostTargetWindow: No eligible application found")
            return nil
        }

        let pid = targetApp.processIdentifier
        let appName = targetApp.localizedName ?? "App"
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindowValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)
        guard result == .success, let windowElement = focusedWindowValue else {
            NSLog("[Stay] getFrontmostTargetWindow: AXFocusedWindow failed for '\(appName)' (PID: \(pid), error: \(result.rawValue))")
            return nil
        }
        let element = windowElement as! AXUIElement

        var titleValue: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String) ?? appName

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

        guard isEligible(owner: appName, role: role, bounds: frame) else {
            NSLog("[Stay] getFrontmostTargetWindow: Window not eligible for '\(appName)' (role: \(role), bounds: \(frame))")
            return nil
        }

        let wid = resolveWindowID(element: element, pid: pid, frame: frame)
        guard let wid else {
            NSLog("[Stay] getFrontmostTargetWindow: Could not resolve CGWindowID for '\(appName)' (bounds: \(frame))")
            return nil
        }

        NSLog("[Stay] getFrontmostTargetWindow: Found target window '\(title)' (wid: \(wid), pid: \(pid), bounds: \(frame))")
        return TargetWindow(
            id: wid,
            pid: pid,
            title: title,
            bundleID: targetApp.bundleIdentifier,
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
        var candidatePIDWid: CGWindowID?
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            if abs(rect.origin.x - frame.origin.x) < 10 && abs(rect.origin.y - frame.origin.y) < 10 {
                return wid
            }
            if abs(rect.width - frame.width) < 10 && abs(rect.height - frame.height) < 10 {
                candidatePIDWid = wid
            }
        }
        return candidatePIDWid
    }
}
