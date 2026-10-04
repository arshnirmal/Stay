import Foundation
import AppKit
import CoreGraphics

/// A normal-layer on-screen window, as reported by the Window Server.
public struct ZWindow: Sendable {
    public let wid: CGWindowID
    public let pid: pid_t
    public let owner: String
    public let title: String
    public let layer: Int
    public let bounds: CGRect
}

/// Reads the Window Server's global front-to-back window ordering.
///
/// `CGWindowListCopyWindowInfo(.optionOnScreenOnly, ...)` returns windows in
/// front-to-back order, which is the only unprivileged way to observe the
/// z-order the user actually sees.
public enum ZOrderService {

    /// Front-to-back list of ordinary application windows (layer 0).
    ///
    /// Higher layers (menu bar, Dock, cursor, wallpaper) are excluded because
    /// they are never in contention with an app window.
    public static func snapshot() -> [ZWindow] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return list.compactMap { item -> ZWindow? in
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0,
                  let widNum = item[kCGWindowNumber as String] as? NSNumber,
                  let pidNum = item[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsDict = item[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }

            return ZWindow(
                wid: CGWindowID(widNum.uint32Value),
                pid: pid_t(pidNum.int32Value),
                owner: item[kCGWindowOwnerName as String] as? String ?? "Unknown",
                title: item[kCGWindowName as String] as? String ?? "",
                layer: layer,
                bounds: bounds
            )
        }
    }

    public static func find(_ wid: CGWindowID, in list: [ZWindow]) -> (index: Int, window: ZWindow)? {
        guard let idx = list.firstIndex(where: { $0.wid == wid }) else { return nil }
        return (idx, list[idx])
    }

    /// Windows drawn in front of `wid` that visually overlap it.
    ///
    /// This — not raw z-index — is the user-visible definition of "buried":
    /// a window ahead of ours on another display or in a non-overlapping
    /// region hides nothing.
    public static func occluders(of wid: CGWindowID, in list: [ZWindow]) -> [ZWindow] {
        guard let (idx, target) = find(wid, in: list) else { return [] }
        guard idx > 0 else { return [] }
        return list[0..<idx].filter { $0.bounds.intersects(target.bounds) }
    }

    /// Fraction of the target's area covered by windows in front of it (0...1).
    ///
    /// Approximated as the largest single-occluder overlap, which is adequate
    /// for classifying "fully covered" vs "grazed at an edge".
    public static func occludedFraction(of wid: CGWindowID, in list: [ZWindow]) -> Double {
        guard let (_, target) = find(wid, in: list) else { return 0 }
        let area = target.bounds.width * target.bounds.height
        guard area > 0 else { return 0 }

        let maxOverlap = occluders(of: wid, in: list)
            .map { $0.bounds.intersection(target.bounds) }
            .map { $0.width * $0.height }
            .max() ?? 0

        return Double(maxOverlap / area)
    }

    /// Resolves the AX element for a Window Server window id.
    public static func axElement(for wid: CGWindowID, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windowsRef,
              CFGetTypeID(windowsRef) == CFArrayGetTypeID()
        else { return nil }

        let array = windowsRef as! CFArray
        for i in 0..<CFArrayGetCount(array) {
            guard let raw = CFArrayGetValueAtIndex(array, i) else { continue }
            let element = unsafeBitCast(raw, to: AXUIElement.self)
            var candidate: CGWindowID = 0
            if _AXUIElementGetWindow(element, &candidate) == .success, candidate == wid {
                return element
            }
        }
        return nil
    }
}
