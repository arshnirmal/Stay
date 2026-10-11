import Foundation

public struct PowerState: Sendable, Equatable {
    public let isLowPower: Bool
    public let isOnBattery: Bool

    public init(isLowPower: Bool, isOnBattery: Bool) {
        self.isLowPower = isLowPower
        self.isOnBattery = isOnBattery
    }

    public var targetFPS: Int {
        if isLowPower { return 15 }
        if isOnBattery { return 30 }
        return 60
    }
}
