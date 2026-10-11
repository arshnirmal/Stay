import Testing
import AppKit
@testable import StayCore

@Suite("Peeker Layout Calculation Tests")
@MainActor
struct PeekerLayoutTests {
    let mockTarget = TargetWindow(
        id: 101,
        pid: 501,
        title: "Terminal",
        bundleID: "com.apple.Terminal",
        bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
        role: "AXWindow"
    )

    let mockScreenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let mockVisibleFrame = NSRect(x: 0, y: 30, width: 1920, height: 1025)

    @Test("In-place frame calculation converts to Cocoa coordinate origin")
    func testInPlaceFrameCalculation() {
        let frame = OverlayWindowManager.calculateFrame(
            for: mockTarget,
            configuration: PeekerConfiguration(mode: .inPlace),
            screenFrame: mockScreenFrame,
            visibleFrame: mockVisibleFrame
        )
        #expect(frame.origin.x == 100)
        // 1080 - 100 (top) - 600 (height) = 380
        #expect(frame.origin.y == 380)
        #expect(frame.size.width == 800)
        #expect(frame.size.height == 600)
    }

    @Test("Corner thumbnail calculation preserves aspect ratio and 16pt margin")
    func testCornerThumbnailBottomRight() {
        let config = PeekerConfiguration(mode: .corner(.bottomRight), scaleRatio: 0.30)
        let frame = OverlayWindowManager.calculateFrame(
            for: mockTarget,
            configuration: config,
            screenFrame: mockScreenFrame,
            visibleFrame: mockVisibleFrame
        )

        let expectedWidth: CGFloat = 1920 * 0.30 // 576
        let expectedHeight: CGFloat = 576 / (800.0 / 600.0) // 432
        let expectedX: CGFloat = mockVisibleFrame.maxX - expectedWidth - 16
        let expectedY: CGFloat = mockVisibleFrame.minY + 16

        #expect(frame.size.width == expectedWidth)
        #expect(frame.size.height == expectedHeight)
        #expect(frame.origin.x == expectedX)
        #expect(frame.origin.y == expectedY)
    }

    @Test("Corner thumbnail calculation for TopLeft")
    func testCornerThumbnailTopLeft() {
        let config = PeekerConfiguration(mode: .corner(.topLeft), scaleRatio: 0.30)
        let frame = OverlayWindowManager.calculateFrame(
            for: mockTarget,
            configuration: config,
            screenFrame: mockScreenFrame,
            visibleFrame: mockVisibleFrame
        )

        let expectedWidth: CGFloat = 1920 * 0.30
        let expectedHeight: CGFloat = expectedWidth / (800.0 / 600.0)
        let expectedX: CGFloat = mockVisibleFrame.minX + 16
        let expectedY: CGFloat = mockVisibleFrame.maxY - expectedHeight - 16

        #expect(frame.origin.x == expectedX)
        #expect(frame.origin.y == expectedY)
    }
}
