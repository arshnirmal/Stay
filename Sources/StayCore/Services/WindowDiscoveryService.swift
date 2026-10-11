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
