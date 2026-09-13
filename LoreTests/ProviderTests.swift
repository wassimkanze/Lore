import XCTest
import SwiftData
#if SWIFT_PACKAGE
@testable import LoreCore
#else
@testable import Lore
#endif

private func fixture(_ name: String, _ ext: String) -> URL {
    #if SWIFT_PACKAGE
    return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")!
    #else
    return Bundle(for: ProviderParsingTests.self).url(forResource: name, withExtension: ext, subdirectory: "Fixtures")!
    #endif
}

final class ProviderParsingTests: XCTestCase {
    func testClaudeDeduplicatesMessagesAndNormalizesCacheInput() throws {
        let session = try XCTUnwrap(ClaudeCodeSessionParser().parse(at: fixture("claude", "jsonl")))
        XCTAssertEqual(session.provider, "Claude Code"); XCTAssertEqual(session.model, "claude-test")
        XCTAssertEqual(session.inputTokens, 115); XCTAssertEqual(session.outputTokens, 16)
        XCTAssertEqual(session.cachedTokens, 100); XCTAssertEqual(session.workingDirectory, "/example/project")
        XCTAssertEqual(session.intervals.count, 1)
        XCTAssertEqual(session.endedAt?.timeIntervalSince(session.startedAt), 600)
        XCTAssertNotEqual(session.id, StableID.session(provider: "Codex", sourceID: session.sourceID))
    }
    func testGeminiLegacyJSONIgnoresContentAndReplacesRepeatedMessages() throws {
        let session = try XCTUnwrap(GeminiSessionParser().parse(at: fixture("gemini", "json")))
        XCTAssertEqual(session.provider, "Gemini CLI"); XCTAssertEqual(session.model, "gemini-test")
        XCTAssertEqual(session.inputTokens, 100); XCTAssertEqual(session.outputTokens, 29)
        XCTAssertEqual(session.cachedTokens, 60); XCTAssertNil(session.workingDirectory)
        XCTAssertEqual(session.intervals.first?.end.timeIntervalSince(session.intervals[0].start), 600)
    }
    func testGeminiJSONLUpdatesRewindsAndCheckpoints() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let initial = """
        {"sessionId":"gemini-lines","projectHash":"unknown","startTime":"2026-09-10T10:00:00Z"}
        {"id":"u1","type":"user","timestamp":"2026-09-10T10:00:00Z"}
        {"id":"m1","type":"gemini","timestamp":"2026-09-10T10:05:00Z","model":"gemini-test","tokens":{"input":100,"output":20,"thoughts":5,"cached":50}}
        {"id":"m1","type":"gemini","timestamp":"2026-09-10T10:06:00Z","model":"gemini-test","tokens":{"input":100,"output":22,"thoughts":5,"cached":50}}
        {"id":"u2","type":"user","timestamp":"2026-09-10T12:00:00Z"}
        {"id":"m2","type":"gemini","timestamp":"2026-09-10T12:05:00Z","model":"removed-model","tokens":{"input":500,"output":50}}
        {"$rewindTo":"u2"}
        {"$set":{"summary":"SANITIZED_PRIVATE_MARKER"}}
        unfinished
        """
        try Data(initial.utf8).write(to: url)
        let session = try XCTUnwrap(GeminiSessionParser().parse(at: url))
        XCTAssertEqual(session.inputTokens, 100); XCTAssertEqual(session.outputTokens, 27)
        XCTAssertEqual(session.model, "gemini-test"); XCTAssertEqual(session.intervals.count, 1)
        let checkpoint = """
        {"$set":{"messages":[{"id":"new","type":"gemini","model":"new-model","timestamp":"2026-09-10T13:00:00Z","tokens":{"input":5,"output":2}}]}}
        """
        try Data((initial + "\n" + checkpoint).utf8).write(to: url)
        let replaced = try XCTUnwrap(GeminiSessionParser().parse(at: url))
        XCTAssertEqual(replaced.inputTokens, 5); XCTAssertEqual(replaced.outputTokens, 2); XCTAssertEqual(replaced.model, "new-model")
    }
    func testInvalidCountersAndMissingMetadataAreSafe() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("""
        {"type":"assistant","sessionId":"safe","timestamp":"2026-09-10T10:00:00Z","message":{"id":"one","usage":{"input_tokens":-2,"output_tokens":"changed"}}}
        """.utf8).write(to: url)
        let session = try XCTUnwrap(ClaudeCodeSessionParser().parse(at: url))
        XCTAssertNil(session.inputTokens); XCTAssertNil(session.outputTokens); XCTAssertNil(session.model)
        try Data("{\"unknown\":1}".utf8).write(to: url)
        XCTAssertNil(try ClaudeCodeSessionParser().parse(at: url))
        XCTAssertNil(try GeminiSessionParser().parse(at: url))
        XCTAssertNil(SessionMetadataSupport.sum([Int.max, 1]))
    }
}

@MainActor final class MultiProviderIndexingTests: XCTestCase {
    func testAllProvidersPersistIdempotentlyAndMappingChangesInvalidateCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LoreProviders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let codexRoot = root.appendingPathComponent("codex")
        let claudeRoot = root.appendingPathComponent("claude")
        let geminiRoot = root.appendingPathComponent("gemini")
        let codexFolder = codexRoot.appendingPathComponent("sessions")
        let claudeFolder = claudeRoot.appendingPathComponent("projects/example")
        let geminiFolder = geminiRoot.appendingPathComponent("tmp/example/chats")
        for directory in [codexFolder, claudeFolder, geminiFolder] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let claudeFile = claudeFolder.appendingPathComponent("main.jsonl")
        let geminiFile = geminiFolder.appendingPathComponent("session-example.json")
        try FileManager.default.copyItem(at: fixture("claude", "jsonl"), to: claudeFile)
        try FileManager.default.copyItem(at: fixture("gemini", "json"), to: geminiFile)
        try Data("""
        {"type":"session_meta","timestamp":"2026-09-10T10:00:00Z","payload":{"id":"shared-session-id","cwd":"/example/project"}}
        """.utf8).write(to: codexFolder.appendingPathComponent("session.jsonl"))
        let originalClaude = try Data(contentsOf: claudeFile), originalGemini = try Data(contentsOf: geminiFile)
        let container = try LoreDatabase.make(inMemory: true)
        let worker = IndexingWorker(container: container, integrations: [CodexIntegration(directory: codexRoot), ClaudeCodeIntegration(directory: claudeRoot), GeminiCLIIntegration(directory: geminiRoot), FailingIntegration(directory: root)])
        let first = try await worker.index(), second = try await worker.index()
        XCTAssertEqual(first.indexedSessions, 3); XCTAssertEqual(second.indexedSessions, 3)
        XCTAssertEqual(second.parsedFiles, 0); XCTAssertEqual(first.blocks, second.blocks)
        XCTAssertEqual(second.providers.filter { $0.indexedSessions == 1 }.count, 3)
        XCTAssertEqual(second.providers.last?.discoveryFailed, true)
        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<AISession>())
        XCTAssertEqual(Set(sessions.map(\.id)).count, 3)
        let gemini = try XCTUnwrap(sessions.first { $0.provider == "Gemini CLI" })
        XCTAssertNil(gemini.project); XCTAssertEqual(gemini.blocks.count, 1, "Unresolved sessions must still be visible")
        let marker = geminiFolder.deletingLastPathComponent().appendingPathComponent(".project_root")
        try Data("/example/project\n".utf8).write(to: marker)
        let third = try await worker.index()
        XCTAssertEqual(third.parsedFiles, 1); XCTAssertEqual(third.projects, 1); XCTAssertEqual(third.blocks, 1)
        let fresh = ModelContext(container)
        let blocks = try fresh.fetch(FetchDescriptor<ActivityBlock>())
        XCTAssertEqual(blocks.first?.sessions.count, 3)
        XCTAssertEqual(try Data(contentsOf: claudeFile), originalClaude)
        XCTAssertEqual(try Data(contentsOf: geminiFile), originalGemini)
    }
    func testGeminiRegistryAndClaudeDiscoveryScope() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LoreDiscovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("tmp/example/chats")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("session-one.json")
        try FileManager.default.copyItem(at: fixture("gemini", "json"), to: file)
        try Data("{\"projects\":{\"/example/project\":\"example\"}}".utf8).write(to: root.appendingPathComponent("projects.json"))
        let integration = GeminiCLIIntegration(directory: root)
        XCTAssertEqual(try integration.discoverSessions().count, 1)
        XCTAssertEqual(try integration.parseSession(at: file)?.workingDirectory, "/example/project")
        let nested = root.appendingPathComponent("projects/example/parent/subagents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture("claude", "jsonl"), to: nested.appendingPathComponent("agent.jsonl"))
        XCTAssertTrue(try ClaudeCodeIntegration(directory: root).discoverSessions().isEmpty)
    }
    private struct FailingIntegration: AIProviderIntegration {
        let provider = "Unavailable test provider"
        let directory: URL
        func discoverSessions() throws -> [URL] { throw CocoaError(.fileReadNoPermission) }
        func parseSession(at url: URL) throws -> ParsedSession? { nil }
    }
}
