import Foundation

public enum KeepAwakeMode: String, Sendable, CaseIterable {
    case off, untilTasksFinish, fifteenMinutes, thirtyMinutes, oneHour, twoHours, fourHours
    public var title: String {
        switch self {
        case .off: "Off"
        case .untilTasksFinish: "Until tasks finish"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        }
    }
    public var maximumDuration: TimeInterval {
        switch self {
        case .off: 0
        case .untilTasksFinish: 6 * 60 * 60
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .fourHours: 4 * 60 * 60
        }
    }
}
public struct KeepAwakeConditions: Sendable {
    public var batteryPercent: Int?
    public var onBattery: Bool
    public var thermalLimited: Bool
    public init(batteryPercent: Int? = nil, onBattery: Bool = false, thermalLimited: Bool = false) {
        self.batteryPercent = batteryPercent; self.onBattery = onBattery; self.thermalLimited = thermalLimited
    }
}
public struct KeepAwakePolicy: Sendable {
    public private(set) var mode: KeepAwakeMode = .off
    public private(set) var deadline: Date?
    public private(set) var stopReason: String?
    public init() {}
    public mutating func begin(_ mode: KeepAwakeMode, at now: Date) {
        self.mode = mode; deadline = mode == .off ? nil : now.addingTimeInterval(mode.maximumDuration); stopReason = nil
    }
    public mutating func evaluate(at now: Date, sessions: [LiveSession], conditions: KeepAwakeConditions) -> Bool {
        guard mode != .off else { return false }
        var reason: String?
        if conditions.thermalLimited { reason = "Stopped because the Mac is too warm." }
        else if conditions.onBattery && (conditions.batteryPercent ?? 100) <= 20 { reason = "Stopped at low battery." }
        else if let deadline, now >= deadline { reason = "Keep-awake session ended." }
        else if mode == .untilTasksFinish && !sessions.contains(where: { $0.phase != .completed && $0.phase != .stopped }) {
            reason = "All observed tasks have finished."
        }
        if let reason { mode = .off; deadline = nil; stopReason = reason; return false }
        return true
    }
}
