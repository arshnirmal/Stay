import SwiftUI
import Carbon
import StayCore

@main
struct StayApp: App {
    @StateObject private var coordinator = PinCoordinator.shared

    init() {
        // Register default global hotkey ⌥⌘T (kVK_ANSI_T = 0x11, cmdKey | optionKey)
        _ = HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(cmdKey | optionKey)
        ) {
            Task { @MainActor in
                try? await PinCoordinator.shared.toggleActiveWindow()
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
