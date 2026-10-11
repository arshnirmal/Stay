import Foundation
import CoreGraphics

public enum InteractionMode: String, Sendable, CaseIterable {
    case smartFocus = "Smart Focus"
    case clickThrough = "Click-Through"
}

public final class PinSession: Identifiable, @unchecked Sendable {
    public let id: CGWindowID
    public let target: TargetWindow
    public var opacity: Double
    public var mode: InteractionMode
    public var isStreaming: Bool

    public init(
        target: TargetWindow,
        opacity: Double = 1.0,
        mode: InteractionMode = .smartFocus
    ) {
        self.id = target.id
        self.target = target
        self.opacity = opacity
        self.mode = mode
        self.isStreaming = false
    }
}
