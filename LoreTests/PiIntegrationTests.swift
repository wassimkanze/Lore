import XCTest
#if SWIFT_PACKAGE
@testable import LoreCore
#else
@testable import Lore
#endif

final class PiIntegrationTests: XCTestCase {
    func testScopedDiscoveryAndMetadataOnlyParsing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LorePi-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("agent/sessions/--example-project--")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("session.jsonl")
        let source = """
        {"type":"session","version":3,"id":"source-session","cwd":"/example/project","timestamp":"2026-09-10T10:00:00Z"}
        {"type":"model_change","id":"change","timestamp":"2026-09-10T10:00:01Z","modelId":"ignored"}
        {"type":"message","id":"user","timestamp":"2026-09-10T10:01:00Z","message":{"role":"user","content":"PRIVATE_SENTINEL"}}
        {"type":"message","id":"reply","timestamp":"2026-09-10T10:02:00Z","message":{"role":"assistant","model":"model-one","content":[{"type":"text","text":"PRIVATE_SENTINEL"}],"usage":{"input":10,"output":4,"cacheRead":20,"cacheWrite":5,"reasoning":2},"stopReason":"stop"}}
        {"type":"usage","id":"extra","timestamp":"2026-09-10T10:03:00Z","model":"model-two","usage":{"input":1,"output":2,"cacheRead":3,"cacheWrite":0}}
        {"type":"compaction","id":"compact","timestamp":"2026-09-10T10:04:00Z","summary":"PRIVATE_SENTINEL","usage":{"input":2,"output":1,"cacheRead":0,"cacheWrite":0}}
        {"type":"custom","id":"custom","timestamp":"2026-09-10T11:00:00Z","data":{"secret":"PRIVATE_SENTINEL"}}
        malformed
        """
        try Data(source.utf8).write(to: file)
        try Data("DO NOT READ".utf8).write(to: root.appendingPathComponent("agent/auth.json"))
        let integration = PiIntegration(directory: root)
        XCTAssertEqual(try integration.discoverSessions().map { $0.standardizedFileURL.resolvingSymlinksInPath() }, [file.standardizedFileURL.resolvingSymlinksInPath()])
        let session = try XCTUnwrap(integration.parseSession(at: file))
        XCTAssertEqual(session.provider, "Pi")
        XCTAssertEqual(session.sourceID, "source-session")
        XCTAssertEqual(session.workingDirectory, "/example/project")
        XCTAssertEqual(session.model, "model-two")
        XCTAssertEqual(session.inputTokens, 41)
        XCTAssertEqual(session.outputTokens, 7)
        XCTAssertEqual(session.cachedTokens, 23)
        XCTAssertEqual(session.endedAt?.timeIntervalSince(session.startedAt), 240)
        XCTAssertEqual(try Data(contentsOf: file), Data(source.utf8))
        XCTAssertNotEqual(session.id, StableID.session(provider: "Codex", sourceID: "source-session"))
    }
    func testLiveSignalsUseOnlyLifecycleMetadata() throws {
        let header = Data(#"{"type":"session","id":"pi-session","cwd":"/example/project","timestamp":"2026-09-10T10:00:00Z"}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(header, provider: "Pi")?.sourceID, "pi-session")
        let user = Data(#"{"type":"message","timestamp":"2026-09-10T10:00:01Z","message":{"role":"user","content":"PRIVATE_SENTINEL"}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(user, provider: "Pi")?.signals, [.started])
        let question = Data(#"{"type":"message","timestamp":"2026-09-10T10:00:02Z","message":{"role":"assistant","model":"test-model","stopReason":"toolUse","content":[{"type":"text","text":"PRIVATE_SENTINEL"},{"type":"toolCall","id":"ask","name":"request_user_input","arguments":{"prompt":"PRIVATE_SENTINEL"}}]}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(question, provider: "Pi")?.signals, [.progress, .waiting("ask")])
        let result = Data(#"{"type":"message","timestamp":"2026-09-10T10:00:03Z","message":{"role":"toolResult","toolCallId":"ask","content":"PRIVATE_SENTINEL"}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(result, provider: "Pi")?.signals, [.resolved("ask"), .progress])
        let done = Data(#"{"type":"message","timestamp":"2026-09-10T10:00:04Z","message":{"role":"assistant","stopReason":"stop","content":[]}}"#.utf8)
        XCTAssertEqual(LiveEventParser.parse(done, provider: "Pi")?.signals, [.progress, .completed])
    }
}
