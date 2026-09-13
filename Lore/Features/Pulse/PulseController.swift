import SwiftUI
import Observation

extension PulseDuration {
    var standardMode: KeepAwakeMode { switch self { case .agents: .untilTasksFinish; case .fifteen: .fifteenMinutes; case .thirty: .thirtyMinutes; case .hour: .oneHour; case .twoHours: .twoHours; case .fourHours: .fourHours } }
}

@MainActor @Observable final class PulseController {
    let notch: NotchController
    let preferences: LorePreferences
    private(set) var busy = false
    private(set) var message: String?
    var closedLid: ClosedLidController { notch.closedLid }
    var isActive: Bool { notch.keepAwake.isActive || closedLid.isActive }
    var canStop: Bool { isActive || closedLid.restorationPending }
    var needsSetup: Bool { preferences.pulseMode == .closedLid && !closedLid.isRegistered }
    var rhythm: PulseRhythm { closedLid.isActive ? .closedLidConfirmed : notch.keepAwake.isActive ? .awake : .resting }
    var status: String {
        if busy || closedLid.busy { return "Updating Pulse…" }
        if closedLid.restorationPending { return "Restoring normal sleep…" }
        if closedLid.isActive { return "Lid closed · " + remaining }
        if notch.keepAwake.isActive { return "Stay awake · " + remaining }
        return "At rest"
    }
    var remaining: String {
        if closedLid.isActive { return LoreFormat.duration(closedLid.secondsRemaining) + " left" }
        if notch.keepAwake.isActive {
            if notch.keepAwake.policy.mode == .untilTasksFinish { return "until agents finish" }
            let now = notch.experience.now == .distantPast ? Date.now : notch.experience.now
            return LoreFormat.duration(max(0, (notch.keepAwake.policy.deadline ?? now).timeIntervalSince(now))) + " left"
        }
        return "Off"
    }
    init(notch: NotchController, preferences: LorePreferences = .shared) { self.notch = notch; self.preferences = preferences }
    func toggle() async { if canStop { await stop() } else { await start() } }
    func start() async {
        guard !busy, !isActive else { return }
        busy = true; message = nil; defer { busy = false }
        if preferences.pulseMode == .closedLid {
            await closedLid.refresh()
            guard closedLid.canStart else { message = needsSetup ? "Enable Pulse’s system access from the Pulse page." : closedLid.message ?? "Pulse is not ready yet. Check system access on the Pulse page."; return }
            await closedLid.start(seconds: Double(preferences.pulseDuration.rawValue))
            if !closedLid.isActive { message = closedLid.message }
        } else {
            guard !closedLid.leaseInUse, !closedLid.restorationPending else { message = "Wait for the previous Pulse session to finish."; return }
            notch.choosePower(preferences.pulseDuration.standardMode)
            message = notch.keepAwake.errorMessage ?? notch.keepAwake.policy.stopReason
        }
    }
    func stop() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        notch.choosePower(.off)
        if closedLid.isActive || closedLid.restorationPending { await closedLid.stop() }
        message = closedLid.restorationPending ? closedLid.message : nil
    }
}
