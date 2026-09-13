import Foundation

/// Global state for the single AI indicator. Empty activity is idle, never success.
public struct LiveActivitySummary: Sendable, Equatable {
    public let sessions: [LiveSession]
    public init(_ sessions: [LiveSession]) {
        self.sessions = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: {
            $0.updatedAt >= $1.updatedAt ? $0 : $1
        }).values.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }
    public var activeCount: Int { sessions.filter { $0.phase != .completed && $0.phase != .stopped }.count }
    public var workingCount: Int { sessions.filter { $0.phase == .working }.count }
    public var phase: LivePhase? {
        guard !sessions.isEmpty else { return nil }
        for phase in [LivePhase.needsInput, .working, .uncertain, .stopped] {
            if sessions.contains(where: { $0.phase == phase }) { return phase }
        }
        return .completed
    }
    public var label: String { phase?.label ?? "No active tasks" }
}
