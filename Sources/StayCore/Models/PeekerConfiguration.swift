import Foundation
import CoreGraphics

public enum CornerPosition: String, CaseIterable, Sendable, Codable {
    case bottomRight
    case bottomLeft
    case topLeft
    case topRight

    public var next: CornerPosition {
        switch self {
        case .bottomRight: return .bottomLeft
        case .bottomLeft:  return .topLeft
        case .topLeft:     return .topRight
        case .topRight:    return .bottomRight
        }
    }
}

public enum PeekerDisplayMode: Equatable, Sendable {
    case inPlace
    case corner(CornerPosition)
}

public struct PeekerConfiguration: Equatable, Sendable {
    public var mode: PeekerDisplayMode
    public var opacity: CGFloat
    public var scaleRatio: CGFloat

    public init(
        mode: PeekerDisplayMode = .corner(.bottomRight),
        opacity: CGFloat = 0.90,
        scaleRatio: CGFloat = 0.30
    ) {
        self.mode = mode
        self.opacity = max(0.20, min(1.0, opacity))
        self.scaleRatio = max(0.20, min(0.45, scaleRatio))
    }
}
