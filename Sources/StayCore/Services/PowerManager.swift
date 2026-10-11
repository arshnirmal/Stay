import Foundation
import CoreMedia
import IOKit.ps

public final class PowerManager: @unchecked Sendable {
    public static let shared = PowerManager()

    private let lock = NSLock()
    private var listeners: [@Sendable (PowerState) -> Void] = []

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerModeDidChange),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    public var currentState: PowerState {
        PowerState(
            isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isOnBattery: checkIsOnBattery()
        )
    }

    public func frameInterval(for fps: Int) -> CMTime {
        CMTime(value: 1, timescale: CMTimeScale(fps))
    }

    public func onStateChanged(_ callback: @escaping @Sendable (PowerState) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        listeners.append(callback)
    }

    @objc private func powerModeDidChange() {
        let state = currentState
        lock.lock()
        let callbacks = listeners
        lock.unlock()
        for cb in callbacks {
            cb(state)
        }
    }

    private func checkIsOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
                  let state = desc[kIOPSPowerSourceStateKey as String] as? String else {
                continue
            }
            if state == (kIOPSBatteryPowerValue as String) {
                return true
            }
        }
        return false
    }
}
