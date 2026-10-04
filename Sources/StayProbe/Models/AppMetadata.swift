import Foundation
import AppKit

public struct AppMetadata: Sendable {
    public let pid: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let executableURL: URL?
    public let isTerminated: Bool
    
    public init(from app: NSRunningApplication) {
        self.pid = app.processIdentifier
        self.name = app.localizedName ?? "Unknown Process"
        self.bundleIdentifier = app.bundleIdentifier
        self.executableURL = app.executableURL
        self.isTerminated = app.isTerminated
    }
    
    public init(pid: pid_t, name: String, bundleIdentifier: String? = nil, executableURL: URL? = nil, isTerminated: Bool = false) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.executableURL = executableURL
        self.isTerminated = isTerminated
    }
}
