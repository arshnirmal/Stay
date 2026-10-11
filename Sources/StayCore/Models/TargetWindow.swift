import Foundation
import CoreGraphics

public struct TargetWindow: Identifiable, Sendable, Equatable {
    public let id: CGWindowID
    public let pid: pid_t
    public let title: String
    public let bundleID: String?
    public let bounds: CGRect
    public let role: String

    public init(
        id: CGWindowID,
        pid: pid_t,
        title: String,
        bundleID: String?,
        bounds: CGRect,
        role: String
    ) {
        self.id = id
        self.pid = pid
        self.title = title
        self.bundleID = bundleID
        self.bounds = bounds
        self.role = role
    }
}
