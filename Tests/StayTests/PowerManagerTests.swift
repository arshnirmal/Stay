import Testing
import Foundation
@testable import StayCore

@Suite("PowerManager Tests")
struct PowerManagerTests {
    @Test("PowerManager provides valid initial state")
    func testPowerManagerInitialState() {
        let manager = PowerManager.shared
        let state = manager.currentState
        #expect(state.targetFPS == 15 || state.targetFPS == 30 || state.targetFPS == 60)
    }

    @Test("Frame interval helper maps FPS accurately")
    func testFrameIntervalMapping() {
        let manager = PowerManager.shared
        let interval15 = manager.frameInterval(for: 15)
        #expect(interval15.timescale == 15)
        #expect(interval15.value == 1)

        let interval60 = manager.frameInterval(for: 60)
        #expect(interval60.timescale == 60)
        #expect(interval60.value == 1)
    }
}
