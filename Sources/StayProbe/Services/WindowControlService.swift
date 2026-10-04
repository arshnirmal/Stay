import Foundation
import CoreGraphics
import ApplicationServices

public enum WindowLevelPreset: Int32, Sendable {
    case normal = 0          // kCGNormalWindowLevel
    case floating = 3        // kCGFloatingWindowLevel
    case tornOffMenu = 4     // Above floating
    case modalPanel = 8      // Modal panel
    case utility = 19        // Utility window
    case status = 25         // Status bar overlay
    
    public var description: String {
        switch self {
        case .normal: return "Normal (Level 0)"
        case .floating: return "Floating / Always on Top (Level 3)"
        case .tornOffMenu: return "Torn-off Menu (Level 4)"
        case .modalPanel: return "Modal Panel (Level 8)"
        case .utility: return "Utility (Level 19)"
        case .status: return "Status Level (Level 25)"
        }
    }
}

public final class WindowControlService: @unchecked Sendable {
    public static let shared = WindowControlService()
    
    // Function pointers for SkyLight private API
    private typealias SLSMainConnectionIDFunc = @convention(c) () -> Int32
    private typealias SLSSetWindowLevelFunc = @convention(c) (Int32, CGWindowID, Int32) -> CGError
    private typealias SLSGetWindowLevelFunc = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<Int32>) -> CGError
    
    private var slsMainConnectionID: SLSMainConnectionIDFunc?
    private var slsSetWindowLevel: SLSSetWindowLevelFunc?
    private var slsGetWindowLevel: SLSGetWindowLevelFunc?
    private var connectionID: Int32 = 0
    
    // Track original levels of pinned windows for clean restore
    private var originalLevels: [CGWindowID: Int32] = [:]
    
    public private(set) var isSkyLightAvailable: Bool = false
    
    private init() {
        loadSkyLightSymbols()
    }
    
    private func loadSkyLightSymbols() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            return
        }
        
        if let connSym = dlsym(handle, "SLSMainConnectionID") ?? dlsym(handle, "CGSMainConnectionID") {
            slsMainConnectionID = unsafeBitCast(connSym, to: SLSMainConnectionIDFunc.self)
        }
        
        if let setSym = dlsym(handle, "SLSSetWindowLevel") ?? dlsym(handle, "CGSSetWindowLevel") {
            slsSetWindowLevel = unsafeBitCast(setSym, to: SLSSetWindowLevelFunc.self)
        }
        
        if let getSym = dlsym(handle, "SLSGetWindowLevel") ?? dlsym(handle, "CGSGetWindowLevel") {
            slsGetWindowLevel = unsafeBitCast(getSym, to: SLSGetWindowLevelFunc.self)
        }
        
        if let connFunc = slsMainConnectionID, slsSetWindowLevel != nil {
            connectionID = connFunc()
            isSkyLightAvailable = (connectionID != 0)
        }
    }
    
    // MARK: - Public Accessibility Operations
    
    public func raiseViaAccessibility(element: AXUIElement) -> (success: Bool, error: String?) {
        let result = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if result == .success {
            return (true, nil)
        } else {
            return (false, "AXRaiseAction failed with AXError \(result.rawValue)")
        }
    }
    
    public func checkSettableAttributes(element: AXUIElement) -> [String: Bool] {
        var namesRef: CFArray?
        guard AXUIElementCopyAttributeNames(element, &namesRef) == .success, let namesRef else {
            return [:]
        }
        
        var results: [String: Bool] = [:]
        let names = (namesRef as [AnyObject]).compactMap { $0 as? String }
        for name in names {
            var settable: DarwinBoolean = false
            let err = AXUIElementIsAttributeSettable(element, name as CFString, &settable)
            results[name] = (err == .success && settable.boolValue)
        }
        return results
    }
    
    // MARK: - Window Server Level Operations
    
    public func getWindowLevel(windowID: CGWindowID) -> Int32? {
        guard let getFunc = slsGetWindowLevel, connectionID != 0 else {
            return nil
        }
        var level: Int32 = 0
        let err = getFunc(connectionID, windowID, &level)
        return (err == .success) ? level : nil
    }
    
    public func setWindowLevel(windowID: CGWindowID, level: Int32) -> (success: Bool, error: String?) {
        guard isSkyLightAvailable, let setFunc = slsSetWindowLevel else {
            return (false, "SkyLight window server symbols not loaded or unavailable on this system.")
        }
        
        // Remember previous level if not already remembered
        if originalLevels[windowID] == nil {
            if let current = getWindowLevel(windowID: windowID) {
                originalLevels[windowID] = current
            } else {
                originalLevels[windowID] = WindowLevelPreset.normal.rawValue
            }
        }
        
        let status = setFunc(connectionID, windowID, level)
        if status == .success {
            return (true, nil)
        } else {
            return (false, "SLSSetWindowLevel returned CGError \(status.rawValue)")
        }
    }
    
    public func pinToFloating(windowID: CGWindowID, preset: WindowLevelPreset = .floating) -> (success: Bool, error: String?) {
        return setWindowLevel(windowID: windowID, level: preset.rawValue)
    }
    
    public func unpin(windowID: CGWindowID) -> (success: Bool, error: String?) {
        let original = originalLevels[windowID] ?? WindowLevelPreset.normal.rawValue
        let result = setWindowLevel(windowID: windowID, level: original)
        if result.success {
            originalLevels.removeValue(forKey: windowID)
        }
        return result
    }
    
    public func isPinned(windowID: CGWindowID) -> Bool {
        return originalLevels[windowID] != nil
    }
    
    public var pinnedWindowIDs: [CGWindowID] {
        Array(originalLevels.keys)
    }
}
