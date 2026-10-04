import Foundation
import CoreGraphics
import ApplicationServices

public struct WindowInfo: Sendable {
    public let windowID: CGWindowID?
    public let app: AppMetadata
    public let title: String
    public let role: String
    public let subrole: String?
    public let frame: CGRect?
    public let isMinimized: Bool
    public let isMainWindow: Bool
    public let supportedActions: [String]
    public let supportedAttributes: [String]
    
    public init(
        windowID: CGWindowID?,
        app: AppMetadata,
        title: String,
        role: String,
        subrole: String?,
        frame: CGRect?,
        isMinimized: Bool,
        isMainWindow: Bool,
        supportedActions: [String] = [],
        supportedAttributes: [String] = []
    ) {
        self.windowID = windowID
        self.app = app
        self.title = title
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.isMinimized = isMinimized
        self.isMainWindow = isMainWindow
        self.supportedActions = supportedActions
        self.supportedAttributes = supportedAttributes
    }
}
