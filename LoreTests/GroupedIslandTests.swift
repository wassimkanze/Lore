import XCTest
#if SWIFT_PACKAGE
@testable import LoreCore
#else
@testable import Lore
#endif

final class GroupedIslandTests: XCTestCase {
    private func session(_ id: String, provider: String = "Codex", phase: LivePhase) -> LiveSession {
        LiveSession(id: id, provider: provider, phase: phase, startedAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200))
    }
    func testInstancesGroupByProviderWithAttentionPriority() throws {
        let groups = LiveProviderGroup.make([session("c1", phase: .working), session("c2", phase: .needsInput), session("a", provider: "Claude Code", phase: .working)])
        XCTAssertEqual(groups.count, 2)
        let codex = try XCTUnwrap(groups.first)
        XCTAssertEqual(codex.provider, "Codex"); XCTAssertEqual(codex.activeCount, 2)
        XCTAssertEqual(codex.phase, .needsInput); XCTAssertEqual(codex.sessions.first?.id, "c2")
    }
    func testCompletedTaskDoesNotHideAnotherRunningTask() {
        let group = LiveProviderGroup.make([session("a", phase: .completed), session("b", phase: .working)]).first
        XCTAssertEqual(group?.phase, .working); XCTAssertEqual(group?.activeCount, 1)
        XCTAssertEqual(LiveProviderGroup.make([session("a", phase: .completed), session("b", phase: .completed)]).first?.phase, .completed)
        XCTAssertEqual(LiveProviderGroup.make([session("a", phase: .completed), session("b", phase: .stopped)]).first?.phase, .stopped)
    }
    func testGlobalIndicatorAggregatesAcrossProvidersAndDeduplicates() throws {
        let codex = session("a", phase: .completed)
        let claude = session("b", provider: "Claude Code", phase: .working)
        let combined = LiveActivitySummary([codex, claude, claude])
        XCTAssertEqual(combined.sessions.count, 2)
        XCTAssertEqual(combined.activeCount, 1); XCTAssertEqual(combined.workingCount, 1)
        XCTAssertEqual(combined.phase, .working)
        let attention = session("c", provider: "Gemini CLI", phase: .needsInput)
        XCTAssertEqual(LiveActivitySummary([codex, claude, attention]).phase, .needsInput)
        XCTAssertEqual(LiveProviderGroup.make([codex, claude, attention]).first?.provider, "Gemini CLI")
    }
    func testGlobalIdleAndUnknownNeverIndicateCompletion() {
        XCTAssertNil(LiveActivitySummary([]).phase)
        XCTAssertEqual(LiveActivitySummary([]).activeCount, 0)
        XCTAssertEqual(LiveActivitySummary([session("a", phase: .completed), session("b", provider: "Claude Code", phase: .completed)]).phase, .completed)
        XCTAssertEqual(LiveActivitySummary([session("a", phase: .completed), session("b", phase: .uncertain)]).phase, .uncertain)
        XCTAssertEqual(LiveActivitySummary([session("a", phase: .completed), session("b", phase: .stopped)]).phase, .stopped)
    }
    func testTimedKeepAwakeExpiresAndDoesNotPersistAcrossLaunches() {
        let now = Date(timeIntervalSince1970: 1000)
        var policy = KeepAwakePolicy()
        XCTAssertEqual(policy.mode, .off)
        policy.begin(.thirtyMinutes, at: now)
        XCTAssertTrue(policy.evaluate(at: now.addingTimeInterval(1799), sessions: [], conditions: .init()))
        XCTAssertFalse(policy.evaluate(at: now.addingTimeInterval(1800), sessions: [], conditions: .init()))
        XCTAssertEqual(policy.mode, .off); XCTAssertNil(policy.deadline)
    }
    func testAutoKeepAwakeEndsWithObservedTasks() {
        var policy = KeepAwakePolicy()
        policy.begin(.untilTasksFinish, at: .now)
        XCTAssertTrue(policy.evaluate(at: .now, sessions: [session("one", phase: .needsInput)], conditions: .init()))
        XCTAssertFalse(policy.evaluate(at: .now, sessions: [session("one", phase: .completed)], conditions: .init()))
    }
    func testBatteryAndThermalGuardsReleaseKeepAwake() {
        var policy = KeepAwakePolicy()
        policy.begin(.oneHour, at: .now)
        XCTAssertFalse(policy.evaluate(at: .now, sessions: [], conditions: .init(batteryPercent: 20, onBattery: true)))
        policy.begin(.oneHour, at: .now)
        XCTAssertTrue(policy.evaluate(at: .now, sessions: [], conditions: .init(batteryPercent: 20, onBattery: false)))
        XCTAssertFalse(policy.evaluate(at: .now, sessions: [], conditions: .init(thermalLimited: true)))
    }
}
