import Testing
import Foundation
@testable import StayCore

@Suite("Peeker Configuration Tests")
struct PeekerConfigurationTests {
    @Test("Default configuration values")
    func testDefaultValues() {
        let config = PeekerConfiguration()
        #expect(config.mode == .corner(.bottomRight))
        #expect(config.opacity == 0.90)
        #expect(config.scaleRatio == 0.30)
    }

    @Test("Opacity clamping between 0.20 and 1.0")
    func testOpacityClamping() {
        let low = PeekerConfiguration(opacity: 0.05)
        #expect(low.opacity == 0.20)

        let high = PeekerConfiguration(opacity: 1.5)
        #expect(high.opacity == 1.0)
    }

    @Test("Scale ratio clamping between 0.20 and 0.45")
    func testScaleRatioClamping() {
        let small = PeekerConfiguration(scaleRatio: 0.10)
        #expect(small.scaleRatio == 0.20)

        let large = PeekerConfiguration(scaleRatio: 0.80)
        #expect(large.scaleRatio == 0.45)
    }

    @Test("Corner cycling sequence")
    func testCornerCycling() {
        #expect(CornerPosition.bottomRight.next == .bottomLeft)
        #expect(CornerPosition.bottomLeft.next == .topLeft)
        #expect(CornerPosition.topLeft.next == .topRight)
        #expect(CornerPosition.topRight.next == .bottomRight)
    }
}
