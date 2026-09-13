import XCTest
import SwiftData
#if SWIFT_PACKAGE
@testable import LoreCore
#else
@testable import Lore
#endif

final class AccessPolicyTests: XCTestCase {
    func testRootBoundariesAndTraversal() {
        let policy = RepositoryAccessPolicy(roots: ["/Users/example/Code"])
        XCTAssertTrue(policy.permits("/Users/example/Code"))
        XCTAssertTrue(policy.permits("/Users/example/Code/App/Sources"))
        XCTAssertFalse(policy.permits("/Users/example/Code-copy"))
        XCTAssertFalse(policy.permits("/Users/example/Code/../Documents/private"))
        XCTAssertFalse(policy.permits("relative/path"))
        XCTAssertFalse(RepositoryAccessPolicy(roots: []).permits("/Users/example/Code"))
    }
    func testReadOnlyBookmarkSurvivesStorageRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LoreBookmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        let grant = FolderGrant(purpose: "projects", path: folder.path, bookmark: data)
        let restored = try JSONDecoder().decode(FolderGrant.self, from: JSONEncoder().encode(grant))
        var stale = false
        let resolved = try URL(resolvingBookmarkData: restored.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        XCTAssertFalse(stale)
        XCTAssertEqual(resolved.standardizedFileURL.resolvingSymlinksInPath().path, folder.standardizedFileURL.resolvingSymlinksInPath().path)
    }
    func testSigningRequirementsRejectInjectedValues() {
        XCTAssertNotNil(SignedIdentity.requirement(identifier: PowerHelperIdentity.appID, team: "ABCDEFGHIJ"))
        XCTAssertNil(SignedIdentity.requirement(identifier: "app.lore.mac\" or true", team: "ABCDEFGHIJ"))
        XCTAssertNil(SignedIdentity.requirement(identifier: PowerHelperIdentity.appID, team: "INVALID\""))
    }
}

@MainActor final class AccessIndexingTests: XCTestCase {
    func testUnapprovedProjectIsIndexedWithoutGitEnrichment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LoreAccess-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("test.jsonl")
        try Data("""
        {"type":"session_meta","timestamp":"2026-09-10T10:00:00Z","payload":{"id":"access-test","cwd":"/Users/example/Documents/private-project"}}
        """.utf8).write(to: file)
        let container = try LoreDatabase.make(inMemory: true)
        let worker = IndexingWorker(container: container, codexDirectory: root)
        await worker.configure(integrations: [CodexIntegration(directory: root)], repositoryAccess: RepositoryAccessPolicy(roots: []))
        let report = try await worker.index()
        XCTAssertEqual(report.indexedSessions, 1); XCTAssertEqual(report.projectsNeedingAccess, 1)
        XCTAssertEqual(report.commits, 0); XCTAssertEqual(report.gitFailures, 0)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Project>()).first?.path, "/Users/example/Documents/private-project")
    }
}

final class ClosedLidEngineTests: XCTestCase {
    private let safe = ClosedLidConditions(onACPower: true, batteryPercent: 80, thermalSafe: true)
    private final class Backend: ClosedLidBackend {
        var disabled = false
        var journal = false
        var failEnable = false
        var failRestore = false
        var writes: [Bool] = []
        func isSleepDisabled() throws -> Bool { disabled }
        func setSleepDisabled(_ value: Bool) throws {
            if value && failEnable || !value && failRestore { throw CocoaError(.fileWriteUnknown) }
            disabled = value; writes.append(value)
        }
        func hasRecoveryRecord() throws -> Bool { journal }
        func writeRecoveryRecord() throws { journal = true }
        func clearRecoveryRecord() throws { journal = false }
    }
    func testStartAndStopOnlyOwnLease() {
        let backend = Backend()
        let service = ClosedLidLeaseEngine(backend: backend)
        let start = service.begin(owner: "owner", seconds: 900, now: 100, conditions: safe)
        XCTAssertTrue(start.leaseActive); XCTAssertTrue(start.ownedByClient); XCTAssertTrue(backend.journal)
        XCTAssertFalse(service.end(owner: "other", now: 101).ownedByClient)
        XCTAssertTrue(backend.disabled)
        XCTAssertFalse(service.end(owner: "owner", now: 102).leaseActive)
        XCTAssertEqual(backend.writes, [true, false]); XCTAssertFalse(backend.journal)
    }
    func testHeartbeatExpiryRestoresWithoutApp() {
        let backend = Backend(); let engine = ClosedLidLeaseEngine(backend: backend)
        _ = engine.begin(owner: "app", seconds: 900, now: 100, conditions: safe)
        _ = engine.heartbeat(owner: "app", now: 125, conditions: safe)
        engine.tick(now: 154, conditions: safe); XCTAssertTrue(backend.disabled)
        engine.tick(now: 156, conditions: safe); XCTAssertFalse(backend.disabled); XCTAssertFalse(backend.journal)
    }
    func testLowBatteryAndThermalPressureRestoreSleep() {
        for conditions in [ClosedLidConditions(onACPower: false, batteryPercent: 20, thermalSafe: true),
                           ClosedLidConditions(onACPower: true, batteryPercent: 80, thermalSafe: false),
                           ClosedLidConditions(onACPower: nil, batteryPercent: nil, thermalSafe: true)] {
            let backend = Backend(); let engine = ClosedLidLeaseEngine(backend: backend)
            _ = engine.begin(owner: "app", seconds: 900, now: 100, conditions: safe)
            engine.tick(now: 105, conditions: conditions)
            XCTAssertFalse(backend.disabled); XCTAssertFalse(backend.journal)
        }
    }
    func testExistingOverrideAndInvalidDurationsAreNeverTakenOver() {
        let backend = Backend(); backend.disabled = true
        let engine = ClosedLidLeaseEngine(backend: backend)
        XCTAssertFalse(engine.begin(owner: "app", seconds: 900, now: 100, conditions: safe).leaseActive)
        XCTAssertTrue(backend.writes.isEmpty); XCTAssertFalse(backend.journal)
        backend.disabled = false
        for duration in [Double.nan, .infinity, -1, 0, 14401] {
            XCTAssertFalse(engine.begin(owner: "app", seconds: duration, now: 100, conditions: safe).leaseActive)
        }
        XCTAssertTrue(backend.writes.isEmpty)
    }
    func testCrashRecoveryAndFailedRestoreKeepRecoveryRecord() {
        let backend = Backend(); backend.disabled = true; backend.journal = true; backend.failRestore = true
        let engine = ClosedLidLeaseEngine(backend: backend)
        engine.recover(); XCTAssertTrue(backend.journal); XCTAssertTrue(backend.disabled)
        XCTAssertTrue(engine.status(owner: "app", now: 100).restorationPending)
        XCTAssertFalse(engine.begin(owner: "app", seconds: 900, now: 100, conditions: safe).leaseActive)
        backend.failRestore = false
        engine.tick(now: 105, conditions: safe)
        XCTAssertFalse(backend.disabled); XCTAssertFalse(backend.journal)
    }
    func testFailedActivationRollsBackAndExternalChangeEndsLease() {
        let backend = Backend(); backend.failEnable = true
        let engine = ClosedLidLeaseEngine(backend: backend)
        XCTAssertFalse(engine.begin(owner: "app", seconds: 900, now: 100, conditions: safe).leaseActive)
        XCTAssertFalse(backend.journal)
        backend.failEnable = false
        _ = engine.begin(owner: "app", seconds: 900, now: 100, conditions: safe)
        backend.disabled = false // Another tool changed the setting; do not fight it.
        engine.tick(now: 105, conditions: safe)
        XCTAssertFalse(engine.status(owner: "app", now: 105).leaseActive)
        XCTAssertFalse(backend.journal)
    }
    func testLiveOwnershipStillRestoresIfJournalDisappears() {
        let backend = Backend(); let engine = ClosedLidLeaseEngine(backend: backend)
        _ = engine.begin(owner: "app", seconds: 900, now: 100, conditions: safe)
        backend.journal = false
        _ = engine.end(owner: "app", now: 105)
        XCTAssertFalse(backend.disabled)
    }
    func testFixedDeadlineCannotBeExtendedByHeartbeat() {
        let backend = Backend(); let engine = ClosedLidLeaseEngine(backend: backend)
        _ = engine.begin(owner: "app", seconds: 60, now: 100, conditions: safe)
        _ = engine.heartbeat(owner: "app", now: 120, conditions: safe)
        _ = engine.heartbeat(owner: "app", now: 140, conditions: safe)
        engine.tick(now: 160, conditions: safe)
        XCTAssertFalse(backend.disabled)
    }
    func testLongBatteryLeaseAndUnpluggingKeepTheFixedDeadline() {
        let battery = ClosedLidConditions(onACPower: false, batteryPercent: 80, thermalSafe: true)
        let backend = Backend(); let engine = ClosedLidLeaseEngine(backend: backend)
        let start = engine.begin(owner: "app", seconds: 3600, now: 100, conditions: battery)
        XCTAssertTrue(start.leaseActive); XCTAssertEqual(start.secondsRemaining, 3600)
        _ = engine.end(owner: "app", now: 101)
        _ = engine.begin(owner: "app", seconds: 3600, now: 200, conditions: safe)
        let unplugged = engine.heartbeat(owner: "app", now: 210, conditions: battery)
        XCTAssertTrue(unplugged.leaseActive); XCTAssertEqual(unplugged.secondsRemaining, 3590)
        let reconnected = engine.heartbeat(owner: "app", now: 220, conditions: safe)
        XCTAssertEqual(reconnected.secondsRemaining, 3580)
        engine.tick(now: 3800, conditions: battery)
        XCTAssertFalse(backend.disabled)
    }
    func testShutdownRestoresLiveOwnershipAndPreservesFailedRecovery() {
        let backend = Backend(); let engine = ClosedLidLeaseEngine(backend: backend)
        _ = engine.begin(owner: "app", seconds: 900, now: 100, conditions: safe)
        backend.failRestore = true
        engine.shutdown()
        XCTAssertTrue(backend.journal)
        XCTAssertTrue(engine.status(owner: "app", now: 101).restorationPending)
        backend.failRestore = false; backend.journal = false
        engine.shutdown()
        XCTAssertFalse(backend.disabled)
        XCTAssertFalse(engine.status(owner: "app", now: 102).leaseActive)
    }
}

@MainActor final class PowerCallbackTests: XCTestCase {
    func testXPCErrorFromBackgroundQueueResumesMainActorWithoutIsolationTrap() async {
        do {
            let _: Data = try await withCheckedThrowingContinuation { continuation in
                let gate = PowerReplyGate(continuation)
                let callback = gate.errorHandler
                DispatchQueue.global().async {
                    callback(CocoaError(.xpcConnectionInterrupted))
                    gate.finish(.success(Data())) // A late reply cannot resume a second time.
                }
            }
            XCTFail("Expected the XPC error")
        } catch { XCTAssertEqual((error as NSError).code, CocoaError.xpcConnectionInterrupted.rawValue) }
    }
    func testLateTimeoutCannotReplaceSuccessfulReply() async throws {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let gate = PowerReplyGate(continuation)
            DispatchQueue.global().async {
                gate.finish(.success(Data([42])))
                gate.finish(.failure(CocoaError(.executableLoad)))
            }
        }
        XCTAssertEqual(data, Data([42]))
    }
}
