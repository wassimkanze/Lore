import Foundation

public struct ClosedLidConditions: Sendable {
    public var onACPower: Bool?
    public var batteryPercent: Int?
    public var thermalSafe: Bool
    public var appleSilicon: Bool
    public init(onACPower: Bool?, batteryPercent: Int?, thermalSafe: Bool, appleSilicon: Bool = true) {
        self.onACPower = onACPower; self.batteryPercent = batteryPercent; self.thermalSafe = thermalSafe; self.appleSilicon = appleSilicon
    }
    public var refusal: String? {
        if !appleSilicon { return "This mode requires Apple Silicon." }
        guard onACPower != nil, let batteryPercent else { return "Battery or power status is unavailable. Closed-lid mode is stopped." }
        guard (0...100).contains(batteryPercent) else { return "Battery status is invalid. Closed-lid mode is stopped." }
        if batteryPercent <= 20 { return "Charge the battery above 20% before starting." }
        if !thermalSafe { return "The Mac is too warm for closed-lid mode." }
        return nil
    }
}

public protocol ClosedLidBackend: AnyObject {
    func isSleepDisabled() throws -> Bool
    func setSleepDisabled(_ disabled: Bool) throws
    func hasRecoveryRecord() throws -> Bool
    func writeRecoveryRecord() throws
    func clearRecoveryRecord() throws
}

/// All calls are serialized by the helper. Tests use an in-memory backend: no elevated operations.
public final class ClosedLidLeaseEngine {
    private let backend: any ClosedLidBackend
    private var owner: String?
    private var deadline: TimeInterval = 0
    private var heartbeatDeadline: TimeInterval = 0
    private var recoveryPending = false
    private var message: String?
    public static let heartbeatTimeout: TimeInterval = 30
    public static let maximumDuration: TimeInterval = 4 * 60 * 60
    public init(backend: any ClosedLidBackend) { self.backend = backend }

    public func recover() {
        do {
            if try backend.hasRecoveryRecord() { try restore() }
        } catch { recoveryPending = true; message = "Sleep restoration needs attention. The helper will retry." }
    }
    public func begin(owner client: String, seconds: TimeInterval, now: TimeInterval, conditions: ClosedLidConditions) -> PowerHelperReply {
        guard seconds.isFinite, (60...Self.maximumDuration).contains(seconds) else { return status(owner: client, now: now, message: "Choose a duration between one minute and four hours.") }
        if recoveryPending { return status(owner: client, now: now, message: "A previous session must be restored first.") }
        guard owner == nil else { return status(owner: client, now: now, message: "A closed-lid session is already active.") }
        if let refusal = conditions.refusal { return status(owner: client, now: now, message: refusal) }
        do {
            guard try !backend.isSleepDisabled() else { return status(owner: client, now: now, message: "System sleep is already controlled by another utility.") }
            // Record ownership before changing the persistent system flag.
            try backend.writeRecoveryRecord()
            try backend.setSleepDisabled(true)
            guard try backend.isSleepDisabled() else { throw CocoaError(.featureUnsupported) }
            owner = client; deadline = now + seconds; heartbeatDeadline = now + Self.heartbeatTimeout
            message = conditions.onACPower == false ? "Battery mode · stops at 20% battery or excessive heat." : nil
        } catch {
            recoveryPending = true
            do { try restore(); message = "Closed-lid mode could not be enabled." }
            catch { message = "Sleep restoration needs attention. The helper will retry." }
        }
        return status(owner: client, now: now)
    }
    public func heartbeat(owner client: String, now: TimeInterval, conditions: ClosedLidConditions) -> PowerHelperReply {
        tick(now: now, conditions: conditions)
        guard owner == client else { return status(owner: client, now: now) }
        heartbeatDeadline = now + Self.heartbeatTimeout
        return status(owner: client, now: now)
    }
    public func end(owner client: String, now: TimeInterval) -> PowerHelperReply {
        if recoveryPending { recover(); return status(owner: client, now: now) }
        guard owner == client else { return status(owner: client, now: now, message: owner == nil ? message : "Another Lore instance owns this session.") }
        do { try restore(); message = nil }
        catch { recoveryPending = true; message = "Sleep restoration needs attention. The helper will retry." }
        return status(owner: client, now: now)
    }
    public func tick(now: TimeInterval, conditions: ClosedLidConditions) {
        if recoveryPending {
            do { try restore(); message = "Normal sleep restored." } catch { }
            return
        }
        guard owner != nil else { return }
        do {
            if try !backend.isSleepDisabled() { try restore(); message = "System sleep changed; the session ended."; return }
        } catch { recoveryPending = true; message = "Sleep status could not be verified. Restoring normal sleep."; return }
        let reason = conditions.refusal ?? (now >= deadline ? "Closed-lid session ended." : now >= heartbeatDeadline ? "Lore stopped responding; normal sleep restored." : nil)
        if let reason {
            do { try restore(); message = reason }
            catch { recoveryPending = true; message = "Sleep restoration needs attention. The helper will retry." }
        }
    }
    public func status(owner client: String, now: TimeInterval, message override: String? = nil) -> PowerHelperReply {
        PowerHelperReply(sleepDisabled: try? backend.isSleepDisabled(), leaseActive: owner != nil,
                         ownedByClient: owner == client, secondsRemaining: owner == nil ? 0 : max(0, deadline - now), message: override ?? message, restorationPending: recoveryPending)
    }
    public func shutdown() {
        do { try restore() }
        catch { recoveryPending = true; message = "Sleep restoration needs attention. The helper will retry." }
    }
    private func restore() throws {
        let shouldRestore = owner != nil ? true : try backend.hasRecoveryRecord()
        if shouldRestore {
            if try backend.isSleepDisabled() { try backend.setSleepDisabled(false) }
            guard try !backend.isSleepDisabled() else { throw CocoaError(.featureUnsupported) }
            try backend.clearRecoveryRecord()
        }
        owner = nil; recoveryPending = false; deadline = 0; heartbeatDeadline = 0
    }
}
