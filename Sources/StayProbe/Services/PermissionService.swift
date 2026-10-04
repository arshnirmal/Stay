import Foundation
import ApplicationServices

public final class PermissionService: Sendable {
    public static let shared = PermissionService()
    
    private init() {}
    
    public var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
    
    @discardableResult
    public func promptForAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
