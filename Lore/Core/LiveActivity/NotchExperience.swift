import Foundation

public enum NotchExperiencePolicy {
    public static let successDuration: TimeInterval = 6
    public static let announcementDuration: TimeInterval = 4
    public static let recentDuration: TimeInterval = 20 * 60
    public static let recentLimit = 12
}

public struct NotchAnnouncement: Sendable, Equatable {
    public enum Kind: Sendable { case attention, completed }
    public let kind: Kind
    public let session: LiveSession
    public let count: Int
    public var title: String { count > 1 ? "\(count) tasks" : session.projectName ?? session.provider }
    public var subtitle: String { kind == .completed ? "Finished" : count > 1 ? "Need your attention" : session.statusLabel }
}

/// Transient presentation data. Retaining results here never persists conversations.
/// A frozen list updates values in place and defers insertions/removals until explicit refresh/close.
public struct NotchExperience: Sendable {
    public private(set) var now = Date.distantPast
    public private(set) var current: [LiveSession] = []
    public private(set) var recent: [LiveSession] = []
    public private(set) var rowsAreFrozen = false
    private var frozenRows: [LiveSession] = []
    private var initialized = false
    public init() {}

    public var indicator: LiveActivitySummary {
        LiveActivitySummary(current.filter {
            $0.phase != .completed || now.timeIntervalSince($0.updatedAt) <= NotchExperiencePolicy.successDuration
        })
    }
    public var attention: [LiveSession] { current.filter { $0.phase == .needsInput } }
    private var available: [LiveSession] {
        var values = Dictionary(uniqueKeysWithValues: current.filter { $0.phase != .completed && $0.phase != .stopped }.map { ($0.id, $0) })
        for session in recent where values[session.id] == nil { values[session.id] = session }
        return LiveProviderGroup.make(Array(values.values)).flatMap(\.sessions)
    }
    public var rows: [LiveSession] { rowsAreFrozen ? frozenRows : available }
    public var pendingRowCount: Int {
        guard rowsAreFrozen else { return 0 }
        let known = Set(frozenRows.map(\.id))
        return available.filter { !known.contains($0.id) }.count
    }
    public var groups: [LiveProviderGroup] {
        let displayedRows = self.rows
        var providers: [String] = []
        for row in displayedRows where !providers.contains(row.provider) { providers.append(row.provider) }
        return providers.map { provider in LiveProviderGroup(provider: provider, sessions: displayedRows.filter { $0.provider == provider }) }
    }
    public mutating func suppressNextAnnouncements() { initialized = false }
    public mutating func freezeRows() { frozenRows = available; rowsAreFrozen = true }
    public mutating func releaseRows() { rowsAreFrozen = false; frozenRows.removeAll() }

    @discardableResult public mutating func ingest(_ sessions: [LiveSession], at now: Date) -> NotchAnnouncement? {
        let previous = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        current = LiveActivitySummary(sessions).sessions
        self.now = now
        var outcomes = Dictionary(uniqueKeysWithValues: recent.map { ($0.id, $0) })
        var newAttention: [LiveSession] = [], newCompletions: [LiveSession] = []
        for session in current {
            let changed = previous[session.id]?.phase != session.phase || previous[session.id]?.startedAt != session.startedAt
            if session.phase == .completed || session.phase == .stopped {
                if outcomes[session.id]?.startedAt != session.startedAt || outcomes[session.id]?.phase != session.phase {
                    outcomes[session.id] = session
                }
            }
            if initialized && changed && now.timeIntervalSince(session.updatedAt) < NotchExperiencePolicy.successDuration {
                if session.phase == .needsInput { newAttention.append(session) }
                if session.phase == .completed { newCompletions.append(session) }
            }
        }
        recent = Array(outcomes.values.filter { now.timeIntervalSince($0.updatedAt) < NotchExperiencePolicy.recentDuration }
            .sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }.prefix(NotchExperiencePolicy.recentLimit))
        if rowsAreFrozen {
            var latest = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            for session in recent where latest[session.id] == nil { latest[session.id] = session }
            frozenRows = frozenRows.map { old in
                if let latest = latest[old.id] { return latest }
                if old.phase == .completed || old.phase == .stopped { return old }
                var quiet = old; quiet.phase = .uncertain; quiet.attentionReason = nil
                return quiet
            }
        }
        initialized = true
        if let session = newAttention.first { return NotchAnnouncement(kind: .attention, session: session, count: newAttention.count) }
        if let session = newCompletions.first { return NotchAnnouncement(kind: .completed, session: session, count: newCompletions.count) }
        return nil
    }
}
