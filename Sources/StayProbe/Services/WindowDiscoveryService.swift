import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

// Undocumented CoreGraphics/Accessibility bridge symbol
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

public final class WindowDiscoveryService: Sendable {
    public static let shared = WindowDiscoveryService()
    
    private init() {}
    
    public func getFrontmostApp() -> AppMetadata? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return AppMetadata(from: frontApp)
    }
    
    public func getFocusedWindow(for pid: pid_t) -> (window: WindowInfo, element: AXUIElement)? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        guard result == .success, let windowRef else {
            return nil
        }
        
        guard CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
            return nil
        }
        
        let windowElement = windowRef as! AXUIElement
        let windowInfo = inspect(element: windowElement, pid: pid)
        return (windowInfo, windowElement)
    }
    
    public func inspect(element: AXUIElement, pid: pid_t) -> WindowInfo {
        let app: AppMetadata
        if let runningApp = NSRunningApplication(processIdentifier: pid) {
            app = AppMetadata(from: runningApp)
        } else {
            app = AppMetadata(pid: pid, name: "PID \(pid)")
        }
        
        let title = copyStringAttribute(element, attribute: kAXTitleAttribute as CFString) ?? ""
        let role = copyStringAttribute(element, attribute: kAXRoleAttribute as CFString) ?? "UnknownRole"
        let subrole = copyStringAttribute(element, attribute: kAXSubroleAttribute as CFString)
        let isMinimized = copyBoolAttribute(element, attribute: kAXMinimizedAttribute as CFString) ?? false
        let isMainWindow = copyBoolAttribute(element, attribute: kAXMainAttribute as CFString) ?? false
        
        let frame = getWindowFrame(element)
        let windowID = resolveWindowID(element: element, pid: pid, frame: frame)
        
        var attributeNamesRef: CFArray?
        let attrResult = AXUIElementCopyAttributeNames(element, &attributeNamesRef)
        let supportedAttributes: [String] = (attrResult == .success && attributeNamesRef != nil)
            ? (attributeNamesRef! as [AnyObject]).compactMap { $0 as? String }
            : []
            
        var actionNamesRef: CFArray?
        let actionResult = AXUIElementCopyActionNames(element, &actionNamesRef)
        let supportedActions: [String] = (actionResult == .success && actionNamesRef != nil)
            ? (actionNamesRef! as [AnyObject]).compactMap { $0 as? String }
            : []
            
        return WindowInfo(
            windowID: windowID,
            app: app,
            title: title.isEmpty ? "(untitled window)" : title,
            role: role,
            subrole: subrole,
            frame: frame,
            isMinimized: isMinimized,
            isMainWindow: isMainWindow,
            supportedActions: supportedActions,
            supportedAttributes: supportedAttributes
        )
    }
    
    public func resolveWindowID(element: AXUIElement, pid: pid_t, frame: CGRect?) -> CGWindowID? {
        var wid: CGWindowID = 0
        let status = _AXUIElementGetWindow(element, &wid)
        if status == .success && wid != 0 {
            return wid
        }
        
        // Fallback: match through CGWindowListCopyWindowInfo
        guard let frame else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for item in windowList {
            guard let itemPid = item[kCGWindowOwnerPID as String] as? pid_t, itemPid == pid else {
                continue
            }
            guard let boundsDict = item[kCGWindowBounds as String] as? [String: CGFloat],
                  let itemBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            
            // Check approximate match (accounting for shadow or frame rounding)
            if abs(itemBounds.origin.x - frame.origin.x) < 2.0 &&
               abs(itemBounds.origin.y - frame.origin.y) < 2.0 &&
               abs(itemBounds.size.width - frame.size.width) < 2.0 &&
               abs(itemBounds.size.height - frame.size.height) < 2.0 {
                if let widNumber = item[kCGWindowNumber as String] as? NSNumber {
                    return CGWindowID(widNumber.uint32Value)
                }
            }
        }
        
        return nil
    }
    
    public func getAllOnScreenWindows() -> [[String: Any]] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list
    }
    
    private func copyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let value = valueRef as? String else {
            return nil
        }
        return value
    }
    
    private func copyBoolAttribute(_ element: AXUIElement, attribute: CFString) -> Bool? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let value = valueRef as? Bool else {
            return nil
        }
        return value
    }
    
    private func getWindowFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else {
            return nil
        }
        
        var point = CGPoint.zero
        var size = CGSize.zero
        
        guard CFGetTypeID(posVal) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal) == AXValueGetTypeID(),
              AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else {
            return nil
        }
        
        return CGRect(origin: point, size: size)
    }
}
