import Testing
import Foundation
@testable import StayCore

@Suite("Peeker Toolbar Tests")
struct PeekerToolbarTests {
    @Test("Toggle mode switches between inPlace and corner")
    func testToggleMode() {
        var config = PeekerConfiguration(mode: .corner(.bottomRight))
        if case .corner = config.mode {
            config.mode = .inPlace
        } else {
            config.mode = .corner(.bottomRight)
        }
        #expect(config.mode == .inPlace)
    }

    @Test("Cycle corner advances to next corner")
    func testCycleCorner() {
        var corner = CornerPosition.bottomRight
        corner = corner.next
        #expect(corner == .bottomLeft)
    }
}
