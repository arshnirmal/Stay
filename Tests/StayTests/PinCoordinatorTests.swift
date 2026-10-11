import Testing
import CoreGraphics
@testable import StayCore

@Suite("PinCoordinator Tests")
@MainActor
struct PinCoordinatorTests {
    @Test("Initial state is empty")
    func testInitialState() {
        let coordinator = PinCoordinator.shared
        #expect(coordinator.activeSessions.isEmpty)
    }

    @Test("Unpin cleanly handles nonexistent ID")
    func testUnpinNonexistent() async {
        let coordinator = PinCoordinator.shared
        await coordinator.unpin(windowID: 99999)
        #expect(coordinator.activeSessions[99999] == nil)
    }
}
