import Foundation

public struct LiveMonitorSnapshot: Sendable {
    public var sessions: [LiveSession]
    public var unreadableFiles: Int
}

/// Lightweight polling is independent of historical indexing and confined to an actor.
/// Only file metadata is rescanned every ten seconds; recent logs are tailed every two seconds.
public actor LiveActivityMonitor {
    private struct Tracked {
        var provider: String
        var url: URL
        var reader = IncrementalLogReader()
        var state: LiveSessionState
    }
    private var integrations: [any AIProviderIntegration]
    private var tracked: [String: Tracked] = [:]
    private var lastDiscovery = Date.distantPast
    public init(integrations: [any AIProviderIntegration] = ProviderIntegrations.defaults()) { self.integrations = integrations }
    public func configure(integrations: [any AIProviderIntegration]) {
        self.integrations = integrations; tracked.removeAll(); lastDiscovery = .distantPast
    }
    public func poll(at now: Date = .now) -> LiveMonitorSnapshot {
        var errors = 0
        if now.timeIntervalSince(lastDiscovery) >= LiveActivityPolicy.discoveryInterval {
            lastDiscovery = now
            var found: Set<String> = []
            for integration in integrations {
                let files: [URL]
                do { files = try integration.discoverSessions() }
                catch { errors += 1; continue }
                for url in files where url.pathExtension == "jsonl" {
                    let key = StableID.make(integration.provider, url.path)
                    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    guard now.timeIntervalSince(modified) < LiveActivityPolicy.inputVisibility || tracked[key]?.state.snapshot(at: now) != nil else { continue }
                    found.insert(key)
                    if tracked[key] == nil {
                        tracked[key] = Tracked(provider: integration.provider, url: url, state: LiveSessionState(provider: integration.provider, sourcePath: url.path))
                    }
                }
            }
            tracked = tracked.filter { found.contains($0.key) || $0.value.state.snapshot(at: now) != nil }
        }
        for key in Array(tracked.keys) {
            guard var file = tracked[key] else { continue }
            do {
                let records = try file.reader.read(at: file.url)
                if file.reader.didReset { file.state = LiveSessionState(provider: file.provider, sourcePath: file.url.path) }
                for record in records {
                    if let event = LiveEventParser.parse(record, provider: file.provider) { file.state.consume(event) }
                }
            } catch { errors += 1 }
            tracked[key] = file
        }
        // Archived/copied logs with a shared provider/session ID occupy one badge.
        let sessions = tracked.values.compactMap { $0.state.snapshot(at: now) }
        let unique = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
        return LiveMonitorSnapshot(sessions: unique.values.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }, unreadableFiles: errors)
    }
}
