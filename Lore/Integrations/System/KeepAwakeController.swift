import Foundation
import Observation
import IOKit.pwr_mgt
import IOKit.ps

@MainActor @Observable public final class KeepAwakeController {
    public private(set) var policy = KeepAwakePolicy()
    public private(set) var isActive = false
    public private(set) var errorMessage: String?
    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    public init() {}
    public func select(_ mode: KeepAwakeMode, sessions: [LiveSession], at now: Date = .now) {
        releaseAssertion()
        policy.begin(mode, at: now); errorMessage = nil
        update(sessions: sessions, at: now)
    }
    public func update(sessions: [LiveSession], at now: Date = .now) {
        let needed = policy.evaluate(at: now, sessions: sessions, conditions: Self.conditions())
        if needed && !isActive {
            var id: IOPMAssertionID = 0
            let properties: [String: Any] = [
                kIOPMAssertionTypeKey: kIOPMAssertionTypePreventUserIdleSystemSleep,
                kIOPMAssertionNameKey: "Lore — keep AI development tasks running",
                kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
                kIOPMAssertionTimeoutKey: max(1, (policy.deadline ?? now).timeIntervalSince(now)),
                kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease
            ]
            let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
            if result == kIOReturnSuccess { assertion = id; isActive = true }
            else { policy.begin(.off, at: now); errorMessage = "macOS could not enable keep awake." }
        } else if !needed && isActive { releaseAssertion() }
    }
    public func stop() { policy.begin(.off, at: .now); releaseAssertion() }
    private func releaseAssertion() {
        if isActive { IOPMAssertionRelease(assertion) }
        assertion = 0; isActive = false
    }
    // macOS also releases process-owned assertions when Lore exits or crashes.
    private static func conditions() -> KeepAwakeConditions {
        let thermal = ProcessInfo.processInfo.thermalState
        var value = KeepAwakeConditions(thermalLimited: thermal == .serious || thermal == .critical)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return value }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (details[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            value.onBattery = (details[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            if let current = details[kIOPSCurrentCapacityKey] as? Int, let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                value.batteryPercent = Int(Double(current) / Double(maximum) * 100)
            }
        }
        return value
    }
}
