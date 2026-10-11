import Testing
import Carbon
@testable import StayCore

@Suite("HotkeyService Tests")
struct HotkeyServiceTests {
    @Test("Registration and unregistration lifecycle")
    func testHotkeyLifecycle() {
        let hotkey = HotkeyService.shared
        let success = hotkey.register(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | optionKey)) {}
        #expect(success)
        hotkey.unregisterAll()
    }
}
