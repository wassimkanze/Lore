import Foundation

public struct LiveProviderGroup: Identifiable, Sendable, Equatable {
    public let provider: String
    public let sessions: [LiveSession]
    public var id: String { provider }
    public init(provider: String, sessions: [LiveSession]) { self.provider = provider; self.sessions = sessions }
    public var phase: LivePhase { LiveActivitySummary(sessions).phase ?? .uncertain }
    public var activeCount: Int { sessions.filter { $0.phase != .completed && $0.phase != .stopped }.count }
    public static func make(_ sessions: [LiveSession]) -> [Self] {
        let order = ["Codex", "Claude Code", "Gemini CLI"]
        return Dictionary(grouping: sessions, by: \.provider).map { provider, sessions in
            Self(provider: provider, sessions: sessions.sorted {
                if $0.phase == .needsInput && $1.phase != .needsInput { return true }
                if $1.phase == .needsInput && $0.phase != .needsInput { return false }
                return ($0.startedAt, $0.id) < ($1.startedAt, $1.id)
            })
        }.sorted {
            if ($0.phase == .needsInput) != ($1.phase == .needsInput) { return $0.phase == .needsInput }
            let left = order.firstIndex(of: $0.provider) ?? order.count
            let right = order.firstIndex(of: $1.provider) ?? order.count
            return left == right ? $0.provider < $1.provider : left < right
        }
    }
}
