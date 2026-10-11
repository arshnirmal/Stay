import Testing
import CoreGraphics
@testable import StayCore

@Suite("Window Discovery & Eligibility Tests")
struct WindowEligibilityTests {
    @Test("Rejects system windows like Window Server Menubar and Dock")
    func testRejectsSystemWindows() {
        let service = WindowDiscoveryService.shared
        #expect(!service.isEligible(owner: "Window Server", role: "AXWindow", bounds: CGRect(x: 0, y: 0, width: 1440, height: 24)))
        #expect(!service.isEligible(owner: "Dock", role: "AXApplication", bounds: CGRect(x: 0, y: 800, width: 1440, height: 100)))
        #expect(!service.isEligible(owner: "Notification Centre", role: "AXWindow", bounds: CGRect(x: 1000, y: 0, width: 400, height: 800)))
    }

    @Test("Rejects zero-size or tiny off-screen utility windows")
    func testRejectsTinyWindows() {
        let service = WindowDiscoveryService.shared
        #expect(!service.isEligible(owner: "Safari", role: "AXWindow", bounds: CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect(!service.isEligible(owner: "VS Code", role: "AXWindow", bounds: .zero))
    }

    @Test("Accepts normal interactive app windows")
    func testAcceptsNormalWindows() {
        let service = WindowDiscoveryService.shared
        #expect(service.isEligible(owner: "Safari", role: "AXWindow", bounds: CGRect(x: 100, y: 100, width: 1200, height: 800)))
        #expect(service.isEligible(owner: "Terminal", role: "AXWindow", bounds: CGRect(x: 200, y: 200, width: 800, height: 600)))
    }
}
