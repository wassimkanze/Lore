import Foundation
import IOKit.ps

public enum ClosedLidEnvironment {
    public static func read() -> ClosedLidConditions {
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif
        let thermal = ProcessInfo.processInfo.thermalState
        var result = ClosedLidConditions(onACPower: nil, batteryPercent: nil,
                                         thermalSafe: thermal == .nominal || thermal == .fair, appleSilicon: appleSilicon)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return result }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (details[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            if let state = details[kIOPSPowerSourceStateKey] as? String {
                if state == kIOPSACPowerValue { result.onACPower = true }
                else if state == kIOPSBatteryPowerValue { result.onACPower = false }
            }
            if let current = details[kIOPSCurrentCapacityKey] as? Int, let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                result.batteryPercent = Int(Double(current) / Double(maximum) * 100)
            }
        }
        return result
    }
}
