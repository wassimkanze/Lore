import XCTest
import CoreGraphics
#if SWIFT_PACKAGE
@testable import LoreCore
#else
@testable import Lore
#endif

final class LiveStateTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    func testQuestionProgressResolutionAndFinish() throws {
        var state = LiveSessionState(provider: "Codex", sourcePath: "/fixture/session.jsonl")
        state.consume(LiveEvent(sourceID: "session", cwd: "/example/project", timestamp: date, turnID: "turn", signals: [.started]))
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(1), signals: [.waiting("question")]))
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(2), signals: [.progress]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(3))?.phase, .needsInput)
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(4), signals: [.resolved("different")]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(4))?.phase, .needsInput)
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(5), signals: [.resolved("question")]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(5))?.phase, .working)
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(6), turnID: "turn", signals: [.completed]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(7))?.phase, .completed)
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(8), signals: [.progress]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(9))?.phase, .completed)
        XCTAssertNil(state.snapshot(at: date.addingTimeInterval(52)))
    }
    func testAsyncQuestionsRequireUserReplyNotImmediateToolReturn() {
        var state = LiveSessionState(provider: "Codex", sourcePath: "/fixture")
        state.consume(LiveEvent(timestamp: date, signals: [.started, .waiting("async:one")]))
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(1), signals: [.resolved("one"), .progress]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(2))?.phase, .needsInput)
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(3), signals: [.started]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(3))?.phase, .working)
    }
    func testStaleAndFutureRecordsNeverBecomeSuccess() {
        var state = LiveSessionState(provider: "Codex", sourcePath: "/fixture")
        state.consume(LiveEvent(timestamp: date, signals: [.started]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(301))?.phase, .uncertain)
        XCTAssertNil(state.snapshot(at: date.addingTimeInterval(1801)))
        XCTAssertNil(state.snapshot(at: date.addingTimeInterval(-61)))
    }
    func testLateCompletionCannotCloseANewerTurn() {
        var state = LiveSessionState(provider: "Codex", sourcePath: "/fixture")
        state.consume(LiveEvent(timestamp: date, turnID: "new", signals: [.started]))
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(1), signals: [.started]))
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(2), turnID: "old", signals: [.completed]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(2))?.phase, .working)
        state.consume(LiveEvent(timestamp: date.addingTimeInterval(-1), turnID: "new", signals: [.completed]))
        XCTAssertEqual(state.snapshot(at: date.addingTimeInterval(2))?.phase, .working)
    }
    func testInterruptedTaskHasDistinctTerminalState() {
        var state = LiveSessionState(provider: "Codex", sourcePath: "/fixture")
        state.consume(LiveEvent(timestamp: date, signals: [.started, .stopped]))
        XCTAssertEqual(state.snapshot(at: date)?.phase, .stopped)
    }
}

final class LiveParserTests: XCTestCase {
    func testCodexQuestionAndCompletionMetadataOnly() throws {
        let call = Data(#"{"timestamp":"2026-09-10T10:00:00Z","type":"response_item","payload":{"type":"function_call","name":"functions.request_user_input","call_id":"one","arguments":"PRIVATE_SENTINEL"}}"#.utf8)
        let event = try XCTUnwrap(LiveEventParser.parse(call, provider: "Codex"))
        XCTAssertEqual(event.signals, [.progress, .waiting("one")])
        let result = Data(#"{"timestamp":"2026-09-10T10:01:00Z","type":"response_item","payload":{"type":"function_call_output","call_id":"one","output":"PRIVATE_SENTINEL"}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(result, provider: "Codex")?.signals, [.resolved("one"), .progress])
        let done = Data(#"{"timestamp":"2026-09-10T10:02:00Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn","last_agent_message":"PRIVATE_SENTINEL"}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(done, provider: "Codex")?.signals, [.completed])
        let async = Data(#"{"timestamp":"2026-09-10T10:03:00Z","type":"response_item","payload":{"type":"function_call","name":"functions.request_user_input_async","call_id":"later","arguments":"PRIVATE_SENTINEL"}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(async, provider: "Codex")?.signals, [.progress, .waiting("async:later")])
    }
    func testClaudeQuestionResultsAndExplicitEndTurn() {
        let question = Data(#"{"type":"assistant","timestamp":"2026-09-10T10:00:00Z","sessionId":"one","message":{"model":"claude-test","stop_reason":"tool_use","content":[{"type":"text","text":"PRIVATE_SENTINEL"},{"type":"tool_use","id":"ask","name":"AskUserQuestion","input":{"questions":"PRIVATE_SENTINEL"}}]}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(question, provider: "Claude Code")?.signals, [.progress, .waiting("ask")])
        let answer = Data(#"{"type":"user","timestamp":"2026-09-10T10:01:00Z","message":{"content":[{"type":"tool_result","tool_use_id":"ask","content":"PRIVATE_SENTINEL"}]}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(answer, provider: "Claude Code")?.signals, [.resolved("ask"), .progress])
        let final = Data(#"{"type":"assistant","timestamp":"2026-09-10T10:02:00Z","message":{"stop_reason":"end_turn","content":[]}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(final, provider: "Claude Code")?.signals, [.progress, .completed])
    }
    func testGeminiDoesNotInventCompletionFromMessageTokens() {
        let data = Data(#"{"id":"one","type":"gemini","timestamp":"2026-09-10T10:00:00Z","model":"gemini-test","tokens":{"output":25},"content":"PRIVATE_SENTINEL"}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(data, provider: "Gemini CLI")?.signals, [.progress])
        XCTAssertNil(LiveEventParser.parse(Data("partial".utf8), provider: "Codex"))
    }
}

final class IncrementalReaderTests: XCTestCase {
    func testPartialLinesAndRepeatedPolls() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("one\npart".utf8).write(to: url)
        var reader = IncrementalLogReader()
        XCTAssertEqual(try reader.read(at: url).map { String(decoding: $0, as: UTF8.self) }, ["one"])
        XCTAssertTrue(try reader.read(at: url).isEmpty)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("ial\ntwo\n".utf8)); try handle.close()
        XCTAssertEqual(try reader.read(at: url).map { String(decoding: $0, as: UTF8.self) }, ["partial", "two"])
        XCTAssertFalse(reader.didReset)
        XCTAssertTrue(try reader.read(at: url).isEmpty)
    }
    func testReplacementAndOversizedLineRecovery() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data((String(repeating: "x", count: 500) + "\nvalid\n").utf8).write(to: url)
        var reader = IncrementalLogReader()
        XCTAssertEqual(try reader.read(at: url, maximumLine: 30).map { String(decoding: $0, as: UTF8.self) }, ["valid"])
        try Data("new\n".utf8).write(to: url, options: .atomic)
        XCTAssertEqual(try reader.read(at: url).map { String(decoding: $0, as: UTF8.self) }, ["new"])
        XCTAssertTrue(reader.didReset)
    }
    func testBoundedBootstrapRecoversIdentityAndTail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(("identity\n" + String(repeating: "ignored\n", count: 100) + "last\n").utf8).write(to: url)
        var reader = IncrementalLogReader()
        let lines = try reader.read(at: url, bootstrapLimit: 20).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(lines.first, "identity"); XCTAssertEqual(lines.last, "last")
        XCTAssertLessThan(lines.count, 5)
    }
}

final class NotchLayoutTests: XCTestCase {
    func testNotchGeometryUsesScreenCoordinatesAndAvoidsCamera() throws {
        let layout = NotchGeometry(screen: CGRect(x: -1600, y: 200, width: 1600, height: 1000),
                                   visibleFrame: CGRect(x: -1600, y: 200, width: 1600, height: 968), safeTop: 32,
                                   leftArea: CGRect(x: -1600, y: 1168, width: 700, height: 32), rightArea: CGRect(x: -700, y: 1168, width: 700, height: 32))
        let cutout = try XCTUnwrap(layout.cutout)
        let left = try XCTUnwrap(layout.wing(side: .left, width: 82)), right = try XCTUnwrap(layout.wing(side: .right, width: 44))
        XCTAssertEqual(left.maxX, cutout.minX); XCTAssertEqual(right.minX, cutout.maxX)
        XCTAssertEqual(left.maxY, 1200); XCTAssertEqual(right.height, 32)
        XCTAssertFalse(left.intersects(cutout)); XCTAssertFalse(right.intersects(cutout))
        for scale: CGFloat in [1, 2] {
            let joinedLeft = try XCTUnwrap(layout.joinedWing(side: .left, width: 82, backingScale: scale))
            let joinedRight = try XCTUnwrap(layout.joinedWing(side: .right, width: 44, backingScale: scale))
            XCTAssertEqual(joinedLeft.minX, left.minX)
            XCTAssertEqual(joinedRight.maxX, right.maxX)
            XCTAssertGreaterThan(joinedLeft.maxX, cutout.midX)
            XCTAssertLessThan(joinedRight.minX, cutout.midX)
            XCTAssertEqual(joinedLeft.width - layout.seamOverlap(backingScale: scale), left.width)
            XCTAssertEqual(joinedRight.width - layout.seamOverlap(backingScale: scale), right.width)
        }
    }
    func testFallbackIsBelowMenuBar() {
        let layout = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055), safeTop: 0, leftArea: .zero, rightArea: .zero)
        XCTAssertNil(layout.cutout)
        XCTAssertLessThan(layout.fallback(width: 120).maxY, 1055)
        XCTAssertEqual(layout.fallback(width: 120).midX, 960)
    }
}

final class LiveMonitorTests: XCTestCase, @unchecked Sendable {
    func testLiveFileAppendPublishesFinishWithoutHistoryIndexing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LoreLiveTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("session.jsonl")
        let now = Date()
        let stamp = now.formatted(.iso8601)
        try Data("""
        {"type":"session_meta","payload":{"id":"live-one","cwd":"/example/project"}}
        {"type":"event_msg","timestamp":"\(stamp)","payload":{"type":"task_started","turn_id":"turn"}}

        """.utf8).write(to: file)
        let monitor = LiveActivityMonitor(integrations: [CodexIntegration(directory: root)])
        let first = await monitor.poll(at: now)
        XCTAssertEqual(first.sessions.count, 1); XCTAssertEqual(first.sessions.first?.phase, .working)
        let repeated = await monitor.poll(at: now.addingTimeInterval(1))
        XCTAssertEqual(repeated.sessions, first.sessions)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        let end = now.addingTimeInterval(2).formatted(.iso8601)
        try handle.write(contentsOf: Data("{\"type\":\"event_msg\",\"timestamp\":\"\(end)\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"turn\"}}\n".utf8))
        try handle.close()
        let finished = await monitor.poll(at: now.addingTimeInterval(3))
        XCTAssertEqual(finished.sessions.first?.phase, .completed)
        XCTAssertEqual(finished.sessions.first?.id, first.sessions.first?.id)
        let expired = await monitor.poll(at: now.addingTimeInterval(49))
        XCTAssertTrue(expired.sessions.isEmpty)
    }
}

#if !SWIFT_PACKAGE
import SwiftUI

final class NotchSurfaceAnimationTests: XCTestCase {
    func testEveryExpansionFrameKeepsTheTopEdgeAttached() {
        let canvas = CGRect(x: 0, y: 0, width: 420, height: 360)
        var surface = GrowingNotchSurface(surfaceWidth: 340, surfaceHeight: 120)
        for step in 0...30 {
            let progress = CGFloat(step) / 30
            surface.animatableData = AnimatablePair(340 + 80 * progress, 120 + 240 * progress)
            let bounds = surface.path(in: canvas).boundingRect
            XCTAssertEqual(bounds.minY, canvas.minY, accuracy: 0.001)
            XCTAssertEqual(bounds.midX, canvas.midX, accuracy: 0.001)
            XCTAssertEqual(bounds.height, 120 + 240 * progress, accuracy: 0.001)
        }
    }
}
#endif
