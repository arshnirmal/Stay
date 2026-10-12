import SwiftUI
import Carbon
import StayCore

@main
struct StayApp: App {
    @StateObject private var coordinator = PinCoordinator.shared
    @StateObject private var permissions = PermissionService.shared

    init() {
        // Request missing permissions on launch
        Task { @MainActor in
            PermissionService.shared.checkPermissions()
            if !PermissionService.shared.hasAccessibility || !PermissionService.shared.hasScreenRecording {
                PermissionService.shared.requestAllPermissions()
            }
        }

        // ⌥⇧P: Pin / Unpin Active Window (kVK_ANSI_P = 0x23)
        _ = HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(optionKey | shiftKey)
        ) {
            Task { @MainActor in
                do {
                    try await PinCoordinator.shared.toggleActiveWindow()
                } catch {
                    NSLog("[Stay] ⌥⇧P pin failed: \(error)")
                }
            }
        }

        // ⌥⌘T: Legacy Alias for Pin / Unpin (kVK_ANSI_T = 0x11)
        _ = HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(cmdKey | optionKey)
        ) {
            Task { @MainActor in
                do {
                    try await PinCoordinator.shared.toggleActiveWindow()
                } catch {
                    NSLog("[Stay] ⌥⌘T pin failed: \(error)")
                }
            }
        }

        // ⌥⇧T: Toggle 1:1 In-Place HUD vs Corner Thumbnail
        _ = HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(optionKey | shiftKey)
        ) {
            Task { @MainActor in
                PinCoordinator.shared.toggleActiveMode()
            }
        }

        // ⌥⇧C: Cycle Screen Corner
        _ = HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(optionKey | shiftKey)
        ) {
            Task { @MainActor in
                PinCoordinator.shared.cycleActiveCorner()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("Stay", systemImage: coordinator.activeSessions.isEmpty ? "pin" : "pin.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
