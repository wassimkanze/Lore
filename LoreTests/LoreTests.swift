import XCTest
import SwiftData
#if SWIFT_PACKAGE
@testable import LoreCore
#else
@testable import Lore
#endif

final class ParserTests: XCTestCase {
    func testSanitizedSessionAndDuplicateCounters() throws {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "session", withExtension: "jsonl", subdirectory: "Fixtures")!
        #else
        let url = Bundle(for: Self.self).url(forResource: "session", withExtension: "jsonl", subdirectory: "Fixtures")!
        #endif
        let session = try XCTUnwrap(CodexSessionParser().parse(at: url))
        XCTAssertEqual(session.sourceID, "sanitized-session-1")
        XCTAssertEqual(session.workingDirectory, "/example/project")
        XCTAssertEqual(session.model, "example-model")
        XCTAssertEqual(session.inputTokens, 220)
        XCTAssertEqual(session.outputTokens, 40)
        XCTAssertEqual(session.cachedTokens, 110)
        XCTAssertEqual(session.intervals.count, 2)
        XCTAssertEqual(session.intervals[0].end.timeIntervalSince(session.intervals[0].start), 20 * 60)
        XCTAssertEqual(session.intervals[1].end.timeIntervalSince(session.intervals[1].start), 10 * 60)
    }
    func testMissingFieldsAndPartialRecords() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("""
        {"type":"session_meta","timestamp":"2026-09-08T09:00:00Z","payload":{"id":"minimal"}}
        {"type":"turn_context","timestamp":"invalid","payload":{"model":42}}
        {"type":"event_msg","payload":{"type":"token_count","info":null}}
        {"partial":
        """.utf8).write(to: url)
        let session = try XCTUnwrap(CodexSessionParser().parse(at: url))
        XCTAssertNil(session.model); XCTAssertNil(session.inputTokens); XCTAssertNil(session.endedAt)
        XCTAssertNil(session.workingDirectory)
        XCTAssertEqual(session.intervals.count, 1)
        try Data("{\"type\":\"unknown\"}".utf8).write(to: url)
        XCTAssertNil(try CodexSessionParser().parse(at: url))
    }
    func testStreamingReaderSkipsOversizedLineAndRecovers() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(("short\n" + String(repeating: "x", count: 300_000) + "\nlast").utf8).write(to: url)
        var lines: [String] = []
        try JSONLReader.read(url, maximumLineBytes: 64) { lines.append(String(decoding: $0, as: UTF8.self)) }
        XCTAssertEqual(lines, ["short", "last"])
    }
    func testDateFormatsAndInvalidCounters() throws {
        XCTAssertEqual(MetadataDate.parse("2026-09-08T09:00:00Z"), MetadataDate.parse("2026-09-08T09:00:00.000Z"))
        XCTAssertNotNil(MetadataDate.parse("2026-09-08T09:00:00.123Z"))
        XCTAssertNil(MetadataDate.parse("not a date"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("""
        {"type":"session_meta","timestamp":"2026-09-08T09:00:00Z","payload":{"id":"invalid-counters"}}
        {"type":"token_usage_record","payload":{"thread_token_usage":{"input_tokens":"changed-schema","output_tokens":12,"cached_input_tokens":-1}}}
        """.utf8).write(to: url)
        let session = try XCTUnwrap(CodexSessionParser().parse(at: url))
        XCTAssertNil(session.inputTokens); XCTAssertNil(session.cachedTokens); XCTAssertEqual(session.outputTokens, 12)
    }
}

final class GroupingTests: XCTestCase {
    private func seed(_ id: String, _ project: String, _ start: Double, _ end: Double) -> ActivitySeed {
        ActivitySeed(sessionID: id, projectID: project, interval: ActivityInterval(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end)))
    }
    func testBoundaryOverlapAndProjectIsolation() {
        let seeds = [seed("a", "one", 0, 100), seed("b", "one", 1900, 2000), seed("c", "one", 3801, 4000), seed("d", "two", 50, 500), seed("a", "one", 20, 60)]
        let service = ActivityGroupingService()
        let groups = service.group(seeds)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first?.sessionIDs, ["a", "b"])
        XCTAssertEqual(groups.first?.end, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(service.group(seeds.reversed()), groups)
        XCTAssertEqual(Set(groups.map(\.id)).count, 3)
        XCTAssertEqual(service.group([]), [])
    }
    func testConcurrentTimeUnionAndDayClipping() {
        let intervals = [ActivityInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100)),
                         ActivityInterval(start: Date(timeIntervalSince1970: 50), end: Date(timeIntervalSince1970: 150))]
        XCTAssertEqual(ActivityGroupingService.duration(of: intervals), 150)
        XCTAssertEqual(ActivityGroupingService.duration(of: intervals, within: DateInterval(start: Date(timeIntervalSince1970: 75), end: Date(timeIntervalSince1970: 125))), 50)
    }
    func testStableIdentityFramingAndProjectScopedCommits() {
        XCTAssertNotEqual(StableID.make("a:b", "c"), StableID.make("a", "b:c"))
        XCTAssertEqual(StableID.session(provider: "Codex", sourceID: "1"), StableID.session(provider: "Codex", sourceID: "1"))
        XCTAssertNotEqual(StableID.commit(projectID: "one", hash: "abc"), StableID.commit(projectID: "two", hash: "abc"))
    }
}

final class GitParsingTests: XCTestCase {
    func testNumstatBinaryAndUnusualFilenames() throws {
        let hash = String(repeating: "a", count: 40)
        let data = "\0LORE_COMMIT\0\(hash)\0Example Author\01700000000\0Subject\n\nBody\n\0\n12\t3\tfile\twith\nnewlines.swift\0-\t-\timage.png\0"
        let commit = try XCTUnwrap(GitOutputParser.commits(data).first)
        XCTAssertEqual(commit.hash, hash); XCTAssertEqual(commit.filesChanged, 2)
        XCTAssertEqual(commit.additions, 12); XCTAssertEqual(commit.deletions, 3)
        XCTAssertEqual(commit.message, "Subject\n\nBody")
        XCTAssertTrue(GitOutputParser.commits("\0LORE_COMMIT\0bad\0x\0nope\0message\0").isEmpty)
    }
    func testRemoteCredentialsRemoved() {
        XCTAssertEqual(GitService.sanitizeRemote("https://name:secret@example.com/team/repo.git?token=secret#private"), "https://example.com/team/repo.git")
        XCTAssertEqual(GitService.sanitizeRemote("git@example.com:team/repo.git"), "example.com:team/repo.git")
        XCTAssertNil(GitService.sanitizeRemote(nil))
    }
    func testMissingRepository() {
        XCTAssertThrowsError(try GitService().repository(at: "/not/a/real/lore-test-directory"))
        XCTAssertThrowsError(try GitService().repository(at: "relative/path"))
    }
    func testReadOnlyServiceAgainstDisposableRepository() throws {
        // Fixture setup is the only Git mutation in the test suite, confined to this owned directory.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LoreGitTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func fixtureGit(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + arguments
            process.environment = ["PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                                   "GIT_AUTHOR_NAME": "Example Author", "GIT_AUTHOR_EMAIL": "example@example.invalid",
                                   "GIT_COMMITTER_NAME": "Example Author", "GIT_COMMITTER_EMAIL": "example@example.invalid",
                                   "GIT_AUTHOR_DATE": "2026-09-08T09:05:00Z", "GIT_COMMITTER_DATE": "2026-09-08T09:05:00Z"]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
        try fixtureGit(["init", "-b", "main"])
        let service = GitService()
        let empty = try service.repository(at: root.path)
        XCTAssertNil(empty.remote); XCTAssertEqual(empty.branch, "main")
        let since = MetadataDate.parse("2026-09-08T00:00:00Z")!, until = MetadataDate.parse("2026-09-09T00:00:00Z")!
        XCTAssertTrue(try service.commits(at: root.path, since: since, until: until).isEmpty)
        let file = root.appendingPathComponent("file\twith\nnewline.txt")
        try Data("one\ntwo\n".utf8).write(to: file)
        try fixtureGit(["add", "--", file.lastPathComponent])
        try fixtureGit(["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "commit", "-m", "Sanitized fixture"])
        let indexURL = root.appendingPathComponent(".git/index")
        let beforeIndex = try Data(contentsOf: indexURL)
        let beforeFile = try Data(contentsOf: file)
        let commits = try service.commits(at: root.path, since: since, until: until)
        XCTAssertEqual(commits.count, 1); XCTAssertEqual(commits.first?.additions, 2)
        XCTAssertEqual(commits.first?.deletions, 0); XCTAssertEqual(commits.first?.filesChanged, 1)
        XCTAssertEqual(commits.first?.message, "Sanitized fixture")
        XCTAssertEqual(try Data(contentsOf: indexURL), beforeIndex)
        XCTAssertEqual(try Data(contentsOf: file), beforeFile)
        try fixtureGit(["-c", "core.hooksPath=/dev/null", "checkout", "--detach", "HEAD"])
        XCTAssertNil(try service.repository(at: root.path).branch)
        XCTAssertEqual(try service.commits(at: root.path, since: since, until: until).count, 1)
    }
}

@MainActor final class PersistenceTests: XCTestCase {
    func testCommitGraphPersistsWithHashAndRelationships() throws {
        let container = try LoreDatabase.make(inMemory: true)
        let context = ModelContext(container)
        let project = Project(path: "/example/project", at: .now)
        let metadata = CommitMetadata(hash: String(repeating: "f", count: 40), author: "Example", message: "Sanitized commit", timestamp: .now, additions: 5, deletions: 2, filesChanged: 1)
        context.insert(project)
        let commit = GitCommit(metadata: metadata, project: project)
        context.insert(commit)
        let block = ActivityBlock(id: "block", project: project, start: .now, end: .now)
        context.insert(block); block.commits = [commit]
        try context.save()
        let readContext = ModelContext(container)
        let saved = try XCTUnwrap(readContext.fetch(FetchDescriptor<GitCommit>()).first)
        XCTAssertEqual(saved.hash, metadata.hash); XCTAssertEqual(saved.project?.id, project.id)
        XCTAssertEqual(saved.project?.commits.count, 1)
        XCTAssertEqual(try readContext.fetch(FetchDescriptor<ActivityBlock>()).first?.commits.first?.hash, metadata.hash)
    }
    func testIndexingTwiceIsIdempotentAndStoreReopens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LoreTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("codex/sessions")
        let archive = root.appendingPathComponent("codex/archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let fixture = """
        {"type":"session_meta","timestamp":"2026-09-08T09:00:00Z","payload":{"id":"duplicate","cwd":"\(root.path)"}}
        {"type":"turn_context","timestamp":"2026-09-08T09:00:00Z","payload":{"model":"test-model"}}
        {"type":"event_msg","timestamp":"2026-09-08T09:10:00Z","payload":{"type":"task_complete"}}
        {"type":"token_usage_record","timestamp":"2026-09-09T10:00:00Z","payload":{"thread_token_usage":{"input_tokens":250,"output_tokens":30,"cached_input_tokens":120}}}
        """
        try Data(fixture.utf8).write(to: sessions.appendingPathComponent("a.jsonl"))
        try Data(fixture.utf8).write(to: archive.appendingPathComponent("copy.jsonl"))
        try Data("malformed".utf8).write(to: sessions.appendingPathComponent("bad.jsonl"))
        let store = root.appendingPathComponent("test.store")
        let container = try LoreDatabase.make(url: store)
        let worker = IndexingWorker(container: container, codexDirectory: root.appendingPathComponent("codex"))
        let first = try await worker.index()
        let second = try await worker.index()
        XCTAssertEqual(first.indexedSessions, 1); XCTAssertEqual(second.indexedSessions, 1)
        XCTAssertEqual(second.projects, 1); XCTAssertEqual(second.blocks, 2); XCTAssertEqual(second.skippedFiles, 1)
        XCTAssertEqual(second.parsedFiles, 0, "Unchanged malformed files are cached until they change")
        let reopened = try LoreDatabase.make(url: store)
        let context = ModelContext(reopened)
        let saved = try context.fetch(FetchDescriptor<AISession>())
        XCTAssertEqual(saved.count, 1); XCTAssertEqual(saved.first?.model, "test-model")
        XCTAssertEqual(saved.first?.inputTokens, 250); XCTAssertEqual(saved.first?.activityIntervals.count, 2)
        XCTAssertEqual(saved.first?.project?.sessions.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActivityBlock>()), 2)
        XCTAssertEqual(saved.first?.blocks.count, 2)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActivityBlock>()).allSatisfy { $0.sessions.count == 1 }, "One long-lived session must remain linked to every period")
        try FileManager.default.removeItem(at: root.appendingPathComponent("codex"))
        let missing = try await worker.index()
        XCTAssertFalse(missing.codexDetected); XCTAssertEqual(missing.blocks, 2)
    }
}

final class UsageSummaryTests: XCTestCase {
    func testCachedTokensAreNotAddedAgainAndSessionsAreDeduplicated() {
        let sample = SessionUsage(id: "one", model: "model-a", input: 100, output: 20, cached: 80)
        let summary = UsageSummary([sample, sample, SessionUsage(id: "two", model: "model-b", input: 40, output: 10, cached: 5)])
        XCTAssertEqual(summary.total, 170)
        XCTAssertEqual(summary.cached, 85)
        XCTAssertEqual(summary.sessions, 2)
        XCTAssertEqual(summary.models.map(\.name), ["model-a", "model-b"])
    }
    func testUnavailableCountersRemainUnavailable() {
        let summary = UsageSummary([SessionUsage(id: "one", model: nil, input: nil, output: nil, cached: nil)])
        XCTAssertNil(summary.total); XCTAssertNil(summary.input); XCTAssertNil(summary.cached)
        XCTAssertEqual(summary.sessionsWithUsage, 0)
        XCTAssertEqual(summary.models.first?.name, "Unknown model")
        XCTAssertTrue(UsageSummary([]).models.isEmpty)
    }
    func testModelRankingUsesSessionCountAndPartialUsageIsCounted() {
        let summary = UsageSummary([
            SessionUsage(id: "a", model: "frequent", input: nil, output: 5, cached: nil),
            SessionUsage(id: "b", model: "frequent", input: 10, output: 2, cached: 8),
            SessionUsage(id: "c", model: "expensive", input: 1000, output: 100, cached: 10)
        ])
        XCTAssertEqual(summary.models.first?.name, "frequent")
        XCTAssertEqual(summary.models.first?.sessions, 2)
        XCTAssertEqual(summary.total, 1117)
        XCTAssertEqual(summary.sessionsWithUsage, 3)
    }
}
