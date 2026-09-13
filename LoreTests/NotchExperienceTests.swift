import XCTest
#if SWIFT_PACKAGE
@testable import LoreCore
#else
@testable import Lore
#endif

final class NotchExperienceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func session(_ id: String, phase: LivePhase, time: Date? = nil, provider: String = "Codex") -> LiveSession {
        LiveSession(id: id, provider: provider, projectName: "Example", phase: phase,
                    startedAt: now.addingTimeInterval(-100), updatedAt: time ?? now)
    }
    func testBootstrapAndTaskStartDoNotAnnounce() {
        var store = NotchExperience()
        XCTAssertNil(store.ingest([session("old", phase: .completed)], at: now))
        XCTAssertEqual(store.recent.count, 1)
        XCTAssertNil(store.ingest([session("new", phase: .working)], at: now.addingTimeInterval(1)))
        XCTAssertEqual(store.indicator.phase, .working)
    }
    func testCompletionAnnouncesOnceAndCheckmarkExpiresBeforeRecentResult() throws {
        var store = NotchExperience()
        store.ingest([session("a", phase: .working)], at: now)
        let done = session("a", phase: .completed, time: now.addingTimeInterval(2))
        let notice = try XCTUnwrap(store.ingest([done], at: now.addingTimeInterval(2)))
        XCTAssertEqual(notice.kind, .completed); XCTAssertEqual(notice.title, "Example")
        XCTAssertNil(store.ingest([done], at: now.addingTimeInterval(3)))
        XCTAssertEqual(store.indicator.phase, .completed)
        store.ingest([done], at: now.addingTimeInterval(9))
        XCTAssertNil(store.indicator.phase)
        store.ingest([], at: now.addingTimeInterval(50))
        XCTAssertEqual(store.rows.count, 1); XCTAssertEqual(store.rows.first?.phase, .completed)
        store.ingest([], at: now.addingTimeInterval(1_203))
        XCTAssertTrue(store.rows.isEmpty)
    }
    func testRowsDoNotMoveOrDisappearWhileFrozen() {
        var store = NotchExperience()
        let a = session("a", phase: .working), b = session("b", phase: .working)
        store.ingest([a, b], at: now); store.freezeRows()
        let ids = store.rows.map(\.id)
        let c = session("c", phase: .working, provider: "Claude Code")
        store.ingest([session("a", phase: .completed), session("b", phase: .needsInput), c], at: now.addingTimeInterval(1))
        XCTAssertEqual(store.rows.map(\.id), ids)
        XCTAssertEqual(store.rows[0].phase, .completed); XCTAssertEqual(store.rows[1].phase, .needsInput)
        XCTAssertEqual(store.pendingRowCount, 1)
        store.ingest([c], at: now.addingTimeInterval(60))
        XCTAssertEqual(store.rows.map(\.id), ids)
        XCTAssertEqual(store.rows[0].phase, .completed); XCTAssertEqual(store.rows[1].phase, .uncertain)
        store.freezeRows()
        XCTAssertTrue(store.rows.contains { $0.id == "c" }); XCTAssertEqual(store.pendingRowCount, 0)
    }
    func testRecentOutcomesAreBounded() {
        var store = NotchExperience()
        store.ingest((0..<30).map { session("\($0)", phase: .completed) }, at: now)
        XCTAssertEqual(store.recent.count, NotchExperiencePolicy.recentLimit)
        XCTAssertEqual(store.rows.count, NotchExperiencePolicy.recentLimit)
    }
    func testAttentionWinsOverCompletionAndStoppedTasksStayQuiet() {
        var store = NotchExperience()
        store.ingest([session("a", phase: .working), session("b", phase: .working)], at: now)
        let notice = store.ingest([session("a", phase: .completed), session("b", phase: .needsInput)], at: now.addingTimeInterval(1))
        XCTAssertEqual(notice?.kind, .attention); XCTAssertEqual(notice?.session.id, "b")
        XCTAssertNil(store.ingest([session("b", phase: .stopped)], at: now.addingTimeInterval(2)))
    }
    func testRestartDoesNotReplayAnnouncements() {
        var store = NotchExperience()
        store.ingest([session("a", phase: .working)], at: now)
        store.suppressNextAnnouncements()
        XCTAssertNil(store.ingest([session("a", phase: .completed)], at: now.addingTimeInterval(1)))
        XCTAssertEqual(store.recent.count, 1)
    }
    func testAttentionReasonsUseMetadataNotQuestionContent() throws {
        let question = Data(#"{"type":"response_item","timestamp":"2026-09-11T10:00:00Z","payload":{"type":"function_call","name":"request_user_input","call_id":"one","arguments":"PRIVATE_SENTINEL"}}"#.utf8)
        let event = try XCTUnwrap(LiveEventParser.parse(question, provider: "Codex"))
        XCTAssertEqual(event.attentionReason, .question)
        var state = LiveSessionState(provider: "Codex", sourcePath: "/fixture")
        state.consume(event)
        XCTAssertEqual(state.snapshot(at: event.timestamp!)?.statusLabel, "Awaiting your reply")
        let plan = Data(#"{"type":"assistant","timestamp":"2026-09-11T10:01:00Z","message":{"content":[{"type":"tool_use","id":"plan","name":"ExitPlanMode","input":"PRIVATE_SENTINEL"}]}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(plan, provider: "Claude Code")?.attentionReason, .planApproval)
    }
}

#if !SWIFT_PACKAGE
@MainActor final class NotchReopeningTests: XCTestCase {
    func testQuickReentryRevealsTheSamePeekOnBothSides() async throws {
        for id in [NotchController.agentsID, NotchController.powerID] {
            let controller = NotchController(rendersPanels: false)
            controller.hover(id)
            try await waitForContent(in: controller)
            XCTAssertTrue(controller.contentVisible)
            XCTAssertFalse(controller.showsDetails)
            controller.dismiss()
            XCTAssertFalse(controller.contentVisible)
            controller.panelHover(true)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(controller.selectedID, id)
            XCTAssertTrue(controller.isExpanded)
            XCTAssertTrue(controller.contentVisible)
            XCTAssertFalse(controller.isPinned)
        }
    }

    func testRepeatedReentryDuringInitialRevealAndAfterDetailsAreVisible() async throws {
        let controller = NotchController(rendersPanels: false)
        controller.showDetails(NotchController.agentsID)
        for delay in [20, 180, 20, 180] {
            try await Task.sleep(for: .milliseconds(delay))
            controller.dismiss()
            controller.panelHover(true)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertTrue(controller.contentVisible)
            XCTAssertTrue(controller.isExpanded)
            XCTAssertTrue(controller.showsDetails)
            XCTAssertEqual(controller.selectedID, NotchController.agentsID)
        }
    }

    private func waitForContent(in controller: NotchController) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !controller.contentVisible && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
#endif
