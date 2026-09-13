import Foundation
import SwiftData
import LoreCore

@main struct LoreDiagnostics {
    static func main() async throws {
        if let index = CommandLine.arguments.firstIndex(of: "--validate-store"), CommandLine.arguments.count > index + 1 {
            let container = try LoreDatabase.make(url: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            print("Migrated validation copy: " + verify(container))
            return
        }
        if CommandLine.arguments.contains("--audit-sessions") {
            for integration in ProviderIntegrations.defaults() {
                var samples: [ParsedSession] = []
                for file in (try? integration.discoverSessions()) ?? [] {
                    if let session = try? integration.parseSession(at: file) { samples.append(session) }
                }
                let usage = UsageSummary(samples.map { SessionUsage(id: $0.id, model: $0.model, input: $0.inputTokens, output: $0.outputTokens, cached: $0.cachedTokens) })
                let links = samples.filter { SessionNavigation.codexURL(provider: $0.provider, sourceID: $0.sourceID) != nil }.count
                print("\(integration.provider): \(usage.sessions) sessions; \(usage.sessionsWithUsage) with usage; \(links) valid chat links; input=\(usage.input.map(String.init) ?? "unavailable"), output=\(usage.output.map(String.init) ?? "unavailable"), cached=\(usage.cached.map(String.init) ?? "unavailable")")
            }
            return
        }
        if CommandLine.arguments.contains("--check-power") {
            let power = KeepAwakeController()
            defer { power.stop() }
            power.select(.thirtyMinutes, sessions: [])
            guard power.isActive else {
                throw NSError(domain: "LorePowerCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: power.errorMessage ?? power.policy.stopReason ?? "Power guard prevented the assertion"])
            }
            print("Created a native, timed PreventUserIdleSystemSleep assertion. No display or closed-lid override.")
            power.stop()
            print("Assertion released; keep-awake state is off.")
            return
        }
        // Validation writes only to its own disposable store, never a development repository.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LoreValidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("validation.store")
        let container = try LoreDatabase.make(url: url)
        let worker = IndexingWorker(container: container)
        let first = try await worker.index()
        let second = try await worker.index()
        let reopened = try LoreDatabase.make(url: url)
        let counts = verify(reopened)
        print("First scan: \(first.indexedSessions) sessions, \(first.projects) projects, \(first.commits) commits, \(first.blocks) blocks; \(first.skippedFiles) skipped, \(first.gitFailures) Git errors")
        print("Refresh: \(second.indexedSessions) sessions, \(second.projects) projects, \(second.commits) commits, \(second.blocks) blocks; \(second.parsedFiles) changed files parsed")
        for provider in second.providers {
            print("\(provider.provider): \(provider.indexedSessions) sessions; detected=\(provider.detected), skipped=\(provider.skippedFiles), discoveryFailed=\(provider.discoveryFailed)")
        }
        print("Reopened store: \(counts)")
        guard first.indexedSessions == second.indexedSessions, first.projects == second.projects,
              first.commits == second.commits, first.blocks == second.blocks else {
            throw NSError(domain: "LoreValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Counts changed; inspect whether a live session was appended during validation."])
        }
    }
    @MainActor static func verify(_ container: ModelContainer) -> String {
        let context = ModelContext(container)
        let sessions = (try? context.fetch(FetchDescriptor<AISession>())) ?? []
        let blocks = (try? context.fetch(FetchDescriptor<ActivityBlock>())) ?? []
        let today = Calendar.current.dateInterval(of: .day, for: .now)!
        let todayBlocks = blocks.filter { $0.startedAt < today.end && $0.endedAt >= today.start }
        precondition(blocks.allSatisfy { !$0.sessions.isEmpty }, "Every observed period must retain its sessions")
        return "\(sessions.count) sessions, \(blocks.count) blocks, \(todayBlocks.count) today; \(sessions.filter { $0.model != nil }.count) models, \(sessions.filter { $0.inputTokens != nil }.count) token totals; all block relationships intact"
    }
}
