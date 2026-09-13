import Foundation
import CryptoKit

public enum ActivityPolicy {
    /// A gap longer than 30 minutes starts a new period. This is observed activity,
    /// not a measurement of keyboard time or a claim of uninterrupted work.
    public static let inactivityThreshold: TimeInterval = 30 * 60
}

public struct ActivityInterval: Codable, Sendable, Equatable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = max(start, end) }
    public func overlaps(_ range: DateInterval) -> Bool {
        if start == end { return start >= range.start && start < range.end }
        return start < range.end && end > range.start
    }
}

public enum StableID {
    public static func make(_ components: String...) -> String { make(components) }
    public static func make(_ components: [String]) -> String {
        // Length framing avoids collisions when paths contain separators.
        let value = components.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static func project(path: String) -> String { make("project", path) }
    public static func session(provider: String, sourceID: String) -> String { make(provider, sourceID) }
    public static func commit(projectID: String, hash: String) -> String { make(projectID, hash) }
}

public struct ParsedSession: Codable, Sendable {
    public var sourceID: String
    public var provider: String
    public var model: String?
    public var workingDirectory: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedTokens: Int?
    public var sourcePath: String
    public var intervals: [ActivityInterval]
    public var id: String { StableID.session(provider: provider, sourceID: sourceID) }
}

public struct CommitMetadata: Sendable, Equatable {
    public var hash: String
    public var author: String
    public var message: String
    public var timestamp: Date
    public var additions: Int
    public var deletions: Int
    public var filesChanged: Int
    public init(hash: String, author: String, message: String, timestamp: Date, additions: Int, deletions: Int, filesChanged: Int) {
        self.hash = hash; self.author = author; self.message = message; self.timestamp = timestamp
        self.additions = additions; self.deletions = deletions; self.filesChanged = filesChanged
    }
}

public struct RepositoryMetadata: Sendable {
    public var root: String
    public var branch: String?
    public var remote: String?
}

public enum MetadataDate {
    public static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return (try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)))
            ?? (try? Date(value, strategy: .iso8601))
    }
}
