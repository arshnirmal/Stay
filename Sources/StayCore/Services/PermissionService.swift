import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

@MainActor
public final class PermissionService: ObservableObject {
    public static let shared = PermissionService()

    @Published public private(set) var hasAccessibility: Bool = false
    @Published public private(set) var hasScreenRecording: Bool = false

    private init() {
        checkPermissions()
    }

    public func checkPermissions() {
        hasAccessibility = AXIsProcessTrusted()
        hasScreenRecording = CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public func promptForAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibility = trusted
        return trusted
    }

    @discardableResult
    public func promptForScreenRecording() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        hasScreenRecording = granted
        return granted
    }

    public func requestAllPermissions() {
        promptForAccessibility()
        promptForScreenRecording()
    }

    public func openSystemSettingsAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openSystemSettingsScreenRecording() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
