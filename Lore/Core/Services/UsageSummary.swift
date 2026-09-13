import Foundation

/// Session-wide counters. They cannot be attributed to individual days without per-turn usage.
public struct SessionUsage: Sendable {
    public var id: String
    public var model: String?
    public var input: Int?
    public var output: Int?
    public var cached: Int?
    public init(id: String, model: String?, input: Int?, output: Int?, cached: Int?) {
        self.id = id; self.model = model; self.input = input; self.output = output; self.cached = cached
    }
}

public struct ModelUsage: Identifiable, Sendable {
    public var name: String
    public var sessions: Int
    public var id: String { name }
}

public struct UsageSummary: Sendable {
    public let sessions: Int
    public let sessionsWithUsage: Int
    public let input: Int?
    public let output: Int?
    public let cached: Int?
    public let models: [ModelUsage]
    /// Cached input is already part of input, never added a second time.
    public var total: Int? {
        guard input != nil || output != nil else { return nil }
        return SessionMetadataSupport.sum([input, output])
    }
    public init(_ samples: [SessionUsage]) {
        let unique = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        sessions = unique.count
        sessionsWithUsage = unique.filter { $0.input != nil || $0.output != nil }.count
        func sum(_ values: [Int?]) -> Int? {
            SessionMetadataSupport.sum(values)
        }
        input = sum(unique.map(\.input)); output = sum(unique.map(\.output)); cached = sum(unique.map(\.cached))
        models = Dictionary(grouping: unique, by: { $0.model ?? "Unknown model" })
            .map { ModelUsage(name: $0.key, sessions: $0.value.count) }
            .sorted { $0.sessions == $1.sessions ? $0.name < $1.name : $0.sessions > $1.sessions }
    }
}
