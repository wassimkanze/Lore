import XCTest
import SwiftData
#if SWIFT_PACKAGE
@testable import LoreCore
#else
@testable import Lore
#endif

final class NavigationAndActivityTests: XCTestCase {
    func testConversationRouteUsesSourceUUIDAndRejectsCommandsOrInjectedURLs() {
        let id = "12345678-1234-1234-1234-123456789abc"
        XCTAssertEqual(SessionNavigation.codexURL(provider: "Codex", sourceID: id)?.absoluteString, "codex://threads/" + id)
        for value in ["new", "../settings", "https://example.com", "abc?prompt=hello", StableID.session(provider: "Codex", sourceID: id)] {
            XCTAssertNil(SessionNavigation.codexURL(provider: "Codex", sourceID: value))
        }
        XCTAssertNil(SessionNavigation.codexURL(provider: "Claude Code", sourceID: id))
    }
    func testFinishedTasksDoNotCountTheGapBeforeTheNextTask() {
        func event(_ second: Double, _ boundary: ObservedActivity.Boundary) -> ObservedActivity.Event { .init(date: Date(timeIntervalSince1970: second), boundary: boundary) }
        let intervals = ObservedActivity.intervals([event(0, .started), event(60, .finished), event(900, .started), event(960, .finished)], fallback: .distantPast)
        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(ActivityGroupingService.duration(of: intervals), 120)
        let seeds = intervals.map { ActivitySeed(sessionID: "s", projectID: "p", interval: $0) }
        XCTAssertEqual(ActivityGroupingService().group(seeds).count, 1, "A meaningful period can contain two tasks and a gap")
    }
    func testMidnightEndDoesNotAppearOnTheFollowingDay() {
        let midnight = Date(timeIntervalSince1970: 100)
        let day = DateInterval(start: midnight, duration: 86400)
        XCTAssertFalse(ActivityInterval(start: midnight.addingTimeInterval(-60), end: midnight).overlaps(day))
        XCTAssertTrue(ActivityInterval(start: midnight, end: midnight).overlaps(day))
    }
    func testOverflowDoesNotCrashUsageTotals() {
        let summary = UsageSummary([SessionUsage(id: "a", model: nil, input: .max, output: 1, cached: .max)])
        XCTAssertNil(summary.total)
    }
    func testLidSamplingRequiresActualClosureAndDetectsSleepGaps() {
        var normal = LidObservation()
        normal.record(closed: false, elapsed: 0)
        for i in 1...35 { normal.record(closed: true, elapsed: Double(i)) }
        normal.record(closed: false, elapsed: 36)
        XCTAssertTrue(normal.continuousSamplingConfirmed)
        var slept = LidObservation()
        slept.record(closed: false, elapsed: 0); slept.record(closed: true, elapsed: 1)
        slept.record(closed: false, elapsed: 61)
        XCTAssertFalse(slept.continuousSamplingConfirmed)
        XCTAssertFalse(LidObservation().continuousSamplingConfirmed)
    }
}

@MainActor final class PersistentIndexCacheTests: XCTestCase {
    func testRestartAppendReplacementTruncationAndPrivateContentExclusion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LoreIncremental-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/session.jsonl")
        let cache = root.appendingPathComponent("metadata-cache.json")
        let header = "{\"type\":\"session_meta\",\"timestamp\":\"2026-09-10T10:00:00Z\",\"payload\":{\"id\":\"12345678-1234-1234-1234-123456789abc\",\"instructions\":\"PRIVATE_SENTINEL\"}}\n"
        try Data(header.utf8).write(to: file)
        let container = try LoreDatabase.make(inMemory: true)
        func worker() -> IndexingWorker { IndexingWorker(container: container, integrations: [CodexIntegration(directory: root)], cacheURL: cache) }
        let first = try await worker().index(); XCTAssertEqual(first.parsedFiles, 1)
        let restarted = try await worker().index(); XCTAssertEqual(restarted.parsedFiles, 0)
        XCTAssertFalse(try String(contentsOf: cache, encoding: .utf8).contains("PRIVATE_SENTINEL"))
        let appended = header + "{\"type\":\"turn_context\",\"timestamp\":\"2026-09-10T10:01:00Z\",\"payload\":{\"model\":\"fixture-model\"}}\n"
        try Data(appended.utf8).write(to: file)
        let changed = try await worker().index(); XCTAssertEqual(changed.parsedFiles, 1)
        try Data(appended.utf8).write(to: file, options: .atomic)
        let replaced = try await worker().index(); XCTAssertEqual(replaced.parsedFiles, 1)
        try Data(header.utf8).write(to: file)
        let truncated = try await worker().index(); XCTAssertEqual(truncated.parsedFiles, 1)
        let sessions = try ModelContext(container).fetch(FetchDescriptor<AISession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sourceID, "12345678-1234-1234-1234-123456789abc")
        try Data("corrupt cache".utf8).write(to: cache)
        let recovered = try await worker().index(); XCTAssertEqual(recovered.parsedFiles, 1)
    }
}

#if !SWIFT_PACKAGE
@MainActor final class PersonalizationTests: XCTestCase {
    func testAppearanceAndPulseChoicesPersistWithoutActivatingPower() throws {
        let name = "LorePreferencesTest-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = LorePreferences(defaults: defaults)
        XCTAssertEqual(preferences.theme, .system)
        XCTAssertEqual(preferences.pulseMode, .standard)
        XCTAssertEqual(preferences.pulseDuration, .hour)
        let notch = NotchController(rendersPanels: false)
        let pulse = PulseController(notch: notch, preferences: preferences)
        preferences.theme = .dark; preferences.accent = .mint; preferences.compact = true
        preferences.reduceMotion = true; preferences.showPulseTime = true
        preferences.pulseMode = .closedLid; preferences.pulseDuration = .fourHours
        let restored = LorePreferences(defaults: defaults)
        XCTAssertEqual(restored.theme, .dark); XCTAssertEqual(restored.accent, .mint)
        XCTAssertTrue(restored.compact); XCTAssertTrue(restored.reduceMotion); XCTAssertTrue(restored.showPulseTime)
        XCTAssertEqual(restored.pulseDuration, .fourHours); XCTAssertEqual(restored.pulseMode, .closedLid)
        XCTAssertFalse(pulse.isActive); XCTAssertFalse(pulse.busy)
    }
    func testAutomaticDurationCannotLeakIntoClosedLidMode() throws {
        let name = "LorePreferencesTest-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = LorePreferences(defaults: defaults)
        preferences.pulseDuration = .agents
        preferences.pulseMode = .closedLid
        XCTAssertEqual(preferences.pulseDuration, .hour)
        defaults.set("invalid", forKey: "appearance.theme")
        XCTAssertEqual(LorePreferences(defaults: defaults).theme, .system)
    }
}
#endif

#if !SWIFT_PACKAGE
@MainActor final class FavoritesAndPresetsTests: XCTestCase {
    func testFavoritesAndNamedPresetsSurviveRestartAndDoNotStartPulse() throws {
        let name = "LorePresetsTest-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = LorePreferences(defaults: defaults)
        preferences.toggleFavorite("project-a"); preferences.toggleFavorite("project-b")
        preferences.toggleFavorite("project-a")
        preferences.pulseMode = .closedLid; preferences.pulseDuration = .twoHours
        XCTAssertTrue(preferences.savePreset(name: "  Long task  "))
        let id = try XCTUnwrap(preferences.pulsePresets.first?.id)
        preferences.pulseDuration = .fourHours
        XCTAssertTrue(preferences.savePreset(name: "long task"))
        XCTAssertEqual(preferences.pulsePresets.count, 1)
        XCTAssertEqual(preferences.pulsePresets.first?.id, id)
        XCTAssertFalse(preferences.savePreset(name: "  "))
        XCTAssertFalse(preferences.savePreset(name: String(repeating: "x", count: 41)))
        let restored = LorePreferences(defaults: defaults)
        XCTAssertEqual(restored.favoriteProjectIDs, ["project-b"])
        let preset = try XCTUnwrap(restored.pulsePresets.first)
        restored.pulseMode = .standard; restored.pulseDuration = .thirty
        let pulse = PulseController(notch: NotchController(rendersPanels: false), preferences: restored)
        restored.applyPreset(preset)
        XCTAssertEqual(restored.pulseMode, .closedLid)
        XCTAssertEqual(restored.pulseDuration, .fourHours)
        XCTAssertFalse(pulse.isActive)
        restored.removePreset(preset.id)
        XCTAssertTrue(LorePreferences(defaults: defaults).pulsePresets.isEmpty)
    }
}
#endif
