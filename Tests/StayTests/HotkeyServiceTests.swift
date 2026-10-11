import Testing
import Carbon
@testable import StayCore

@Suite("HotkeyService Tests")
struct HotkeyServiceTests {
    @Test("Registration and unregistration lifecycle")
    func testHotkeyLifecycle() {
        let hotkey = HotkeyService.shared
        let successPin = hotkey.register(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(optionKey | shiftKey)) {}
        let successMode = hotkey.register(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey | shiftKey)) {}
        let successCorner = hotkey.register(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey | shiftKey)) {}
        #expect(successPin)
        #expect(successMode)
        #expect(successCorner)
        hotkey.unregisterAll()
    }
}
