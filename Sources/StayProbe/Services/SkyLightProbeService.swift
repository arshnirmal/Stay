import Foundation
import CoreGraphics

/// Probe C — elimination probes for the remaining private Window Server entry points.
///
/// Phase 0 proved `SLSSetWindowLevel` from our own connection is silently
/// ignored for foreign windows. These probes close the remaining "did we miss
/// a private API?" question. Every probe verifies by *observed effect*
/// (z-order / level readback), never by return code: Phase 0 established that
/// the Window Server returns `kCGErrorSuccess` while doing nothing.
public final class SkyLightProbeService: @unchecked Sendable {
    public static let shared = SkyLightProbeService()

    private typealias MainConnectionIDFunc = @convention(c) () -> Int32
    private typealias GetWindowOwnerFunc = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias SetWindowLevelFunc = @convention(c) (Int32, CGWindowID, Int32) -> CGError
    private typealias GetWindowLevelFunc = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias SetWindowSubLevelFunc = @convention(c) (Int32, CGWindowID, Int32) -> CGError
    private typealias OrderWindowFunc = @convention(c) (Int32, CGWindowID, Int32, CGWindowID) -> CGError

    private var mainConnectionID: MainConnectionIDFunc?
    private var getWindowOwner: GetWindowOwnerFunc?
    private var setWindowLevel: SetWindowLevelFunc?
    private var getWindowLevel: GetWindowLevelFunc?
    private var setWindowSubLevel: SetWindowSubLevelFunc?
    private var orderWindow: OrderWindowFunc?

    private var cid: Int32 = 0

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            return
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        mainConnectionID = sym("SLSMainConnectionID", MainConnectionIDFunc.self)
        getWindowOwner = sym("SLSGetWindowOwner", GetWindowOwnerFunc.self)
        setWindowLevel = sym("SLSSetWindowLevel", SetWindowLevelFunc.self)
        getWindowLevel = sym("SLSGetWindowLevel", GetWindowLevelFunc.self)
        setWindowSubLevel = sym("SLSSetWindowSubLevel", SetWindowSubLevelFunc.self)
        orderWindow = sym("SLSOrderWindow", OrderWindowFunc.self)
        cid = mainConnectionID?() ?? 0
    }

    public func run(wid: CGWindowID) {
        print("\n🔬 PROBE C — Private Window Server entry points")
        print(String(repeating: "─", count: 72))
        print("  Target CGWindowID : \(wid)")
        print("  Our connection ID : \(cid)")
        print("  Symbols resolved  : SLSGetWindowOwner=\(getWindowOwner != nil)  "
              + "SLSSetWindowSubLevel=\(setWindowSubLevel != nil)  SLSOrderWindow=\(orderWindow != nil)")

        guard cid != 0 else {
            print("  ❌ No Window Server connection; cannot probe.")
            return
        }

        let ownerCID = probeOwnerConnection(wid: wid)
        probeSetLevelViaOwnerConnection(wid: wid, ownerCID: ownerCID)
        probeSubLevel(wid: wid)
        probeOrderWindow(wid: wid)

        print(String(repeating: "─", count: 72))
    }

    // MARK: - C1: can we learn the owning connection?

    private func probeOwnerConnection(wid: CGWindowID) -> Int32? {
        guard let getWindowOwner else {
            print("\n  [C1] SLSGetWindowOwner .............. SYMBOL MISSING")
            return nil
        }
        var owner: Int32 = 0
        let err = getWindowOwner(cid, wid, &owner)
        if err == .success && owner != 0 {
            print("\n  [C1] SLSGetWindowOwner .............. OK → owning cid = \(owner)")
            return owner
        }
        print("\n  [C1] SLSGetWindowOwner .............. FAILED (CGError \(err.rawValue), owner=\(owner))")
        return nil
    }

    // MARK: - C2: does passing the OWNER's cid defeat the ownership check?

    private func probeSetLevelViaOwnerConnection(wid: CGWindowID, ownerCID: Int32?) {
        guard let setWindowLevel, let getWindowLevel else {
            print("  [C2] SLSSetWindowLevel(ownerCID) .... SYMBOL MISSING")
            return
        }
        guard let ownerCID else {
            print("  [C2] SLSSetWindowLevel(ownerCID) .... SKIPPED (no owning cid from C1)")
            return
        }

        var before: Int32 = 0
        _ = getWindowLevel(cid, wid, &before)
        let err = setWindowLevel(ownerCID, wid, 3)
        var after: Int32 = 0
        _ = getWindowLevel(cid, wid, &after)

        let changed = (after != before)
        print("  [C2] SLSSetWindowLevel(ownerCID) .... returned \(err.rawValue), "
              + "level \(before) → \(after)  \(changed ? "✅ EFFECTIVE" : "❌ NO EFFECT")")

        if changed {
            _ = setWindowLevel(ownerCID, wid, before)
            print("       ↩︎ restored level to \(before)")
        }
    }

    // MARK: - C3: sub-level (ordering within a level band)

    private func probeSubLevel(wid: CGWindowID) {
        guard let setWindowSubLevel else {
            print("  [C3] SLSSetWindowSubLevel ........... SYMBOL MISSING")
            return
        }
        let rankBefore = ZOrderService.find(wid, in: ZOrderService.snapshot())?.index
        let err = setWindowSubLevel(cid, wid, 1)
        Thread.sleep(forTimeInterval: 0.15)
        let rankAfter = ZOrderService.find(wid, in: ZOrderService.snapshot())?.index

        let moved = rankBefore != rankAfter
        print("  [C3] SLSSetWindowSubLevel ........... returned \(err.rawValue), "
              + "z-rank \(rankBefore.map(String.init) ?? "?") → \(rankAfter.map(String.init) ?? "?")  "
              + "\(moved ? "✅ EFFECTIVE" : "❌ NO EFFECT")")

        if moved { _ = setWindowSubLevel(cid, wid, 0) }
    }

    // MARK: - C4: direct z-order manipulation

    private func probeOrderWindow(wid: CGWindowID) {
        guard let orderWindow else {
            print("  [C4] SLSOrderWindow ................. SYMBOL MISSING")
            return
        }
        let rankBefore = ZOrderService.find(wid, in: ZOrderService.snapshot())?.index
        // mode 1 = order above, relativeTo 0 = above all windows in its level
        let err = orderWindow(cid, wid, 1, 0)
        Thread.sleep(forTimeInterval: 0.15)
        let rankAfter = ZOrderService.find(wid, in: ZOrderService.snapshot())?.index

        let moved = rankBefore != rankAfter
        print("  [C4] SLSOrderWindow(above, all) ..... returned \(err.rawValue), "
              + "z-rank \(rankBefore.map(String.init) ?? "?") → \(rankAfter.map(String.init) ?? "?")  "
              + "\(moved ? "✅ EFFECTIVE" : "❌ NO EFFECT")")
    }
}
