import Testing
import CoreGraphics
import Foundation
@testable import StayCore

@Suite("Core Domain Model Tests")
struct ModelTests {
    @Test("TargetWindow initialization and equality")
    func testTargetWindow() {
        let window1 = TargetWindow(
            id: 101,
            pid: 500,
            title: "Safari Window",
            bundleID: "com.apple.Safari",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            role: "AXWindow"
        )
        let window2 = TargetWindow(
            id: 101,
            pid: 500,
            title: "Safari Window",
            bundleID: "com.apple.Safari",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            role: "AXWindow"
        )
        #expect(window1 == window2)
        #expect(window1.id == 101)
    }

    @Test("PinSession initial values and mode toggle")
    func testPinSession() {
        let target = TargetWindow(
            id: 202,
            pid: 600,
            title: "TextEdit",
            bundleID: "com.apple.TextEdit",
            bounds: CGRect(x: 100, y: 100, width: 500, height: 400),
            role: "AXWindow"
        )
        let session = PinSession(target: target)
        #expect(session.id == 202)
        #expect(session.mode == .smartFocus)
        #expect(session.opacity == 1.0)
        #expect(session.isStreaming == false)
    }

    @Test("PowerState frame rate computation")
    func testPowerStateFPS() {
        let lowPower = PowerState(isLowPower: true, isOnBattery: true)
        #expect(lowPower.targetFPS == 15)

        let normalBattery = PowerState(isLowPower: false, isOnBattery: true)
        #expect(normalBattery.targetFPS == 30)

        let pluggedIn = PowerState(isLowPower: false, isOnBattery: false)
        #expect(pluggedIn.targetFPS == 60)
    }
}
