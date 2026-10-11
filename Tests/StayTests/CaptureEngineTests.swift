import Testing
import Foundation
import CoreMedia
@testable import StayCore

@Suite("CaptureEngine Lifecycle Tests")
struct CaptureEngineTests {
    @Test("CaptureEngine initial state is unstarted")
    func testCaptureEngineState() {
        let engine = CaptureEngine(windowID: 999) { _ in }
        let isRunning = engine.isRunning
        #expect(!isRunning)
    }
}
