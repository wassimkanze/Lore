import Foundation
import Observation
import IOKit

@MainActor @Observable final class ClosedLidValidation {
    private(set) var running = false
    private(set) var observation = LidObservation()
    private(set) var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var power: ClosedLidController?
    @ObservationIgnored private var startedOnACPower: Bool?
    private struct Report: Codable {
        var date: Date
        var observation: LidObservation
        var sleepRestored: Bool
        var samplingConfirmed: Bool
        var startedOnACPower: Bool?
    }
    init() {
        if let directory = try? LoreDatabase.defaultURL().deletingLastPathComponent(),
           let bytes = try? SessionMetadataSupport.readBounded(directory.appendingPathComponent("last-lid-test.json"), limit: 8192),
           let report = try? JSONDecoder().decode(Report.self, from: bytes) {
            observation = report.observation
            message = "Last check · " + report.date.formatted(date: .abbreviated, time: .shortened) + ": " + (report.samplingConfirmed ? "sampling continued while closed for \(Int(report.observation.closedSeconds))s" : "inconclusive") + (report.sleepRestored ? "; normal sleep was restored." : "; restoration was not confirmed.")
        }
    }
    func start(power: ClosedLidController) async {
        guard !running else { return }
        guard Self.lidClosed() == false else { message = "Open the lid first. Its sensor must be readable."; return }
        await power.refresh()
        guard power.canStart else { message = "Authorize the power service and stop any existing closed-lid session first."; return }
        startedOnACPower = ClosedLidEnvironment.read().onACPower
        await power.start(seconds: 180)
        guard power.isActive else { message = power.message; return }
        self.power = power; running = true; observation = LidObservation()
        message = "Close the lid for 30–60 seconds, then reopen it. Leave the Mac on a ventilated surface."
        let began = ContinuousClock.now
        observation.record(closed: false, elapsed: 0)
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                let duration = began.duration(to: .now).components
                let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                observation.record(closed: Self.lidClosed(), elapsed: elapsed)
                if observation.reopened || elapsed >= 175 || !power.isActive {
                    await finish(); return
                }
            }
        }
    }
    func finish() async {
        guard running else { return }
        task?.cancel(); task = nil
        await power?.stop()
        let restored = power?.statusAvailable == true && power?.isActive == false && power?.restorationPending == false
        let confirmed = observation.continuousSamplingConfirmed && restored
        message = confirmed ? "Lore kept sampling while closed for \(Int(observation.closedSeconds)) seconds. Normal sleep restored. Verify the agent result and display behavior separately." : "Test inconclusive: closed \(Int(observation.closedSeconds))s; longest sampling gap \(String(format: "%.1f", observation.largestGap))s. \(restored ? "Normal sleep restored." : "Check sleep restoration in the power service.")"
        running = false
        if let directory = try? LoreDatabase.defaultURL().deletingLastPathComponent(),
           let bytes = try? JSONEncoder().encode(Report(date: .now, observation: observation, sleepRestored: restored, samplingConfirmed: confirmed, startedOnACPower: startedOnACPower)) {
            try? bytes.write(to: directory.appendingPathComponent("last-lid-test.json"), options: .atomic)
        }
    }
    /// Read only the clamshell boolean; never modify power or display registry values.
    private static func lidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }
}
