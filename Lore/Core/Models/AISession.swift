import Foundation
import SwiftData

@Model public final class AISession {
    @Attribute(.unique) public var id: String
    public var provider: String
    public var sourceID: String? = nil
    public var model: String?
    public var project: Project?
    public var blocks: [ActivityBlock] = []
    public var startedAt: Date
    public var endedAt: Date?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedTokens: Int?
    public var sourcePath: String
    /// Only timestamp pairs are retained, so grouping survives refreshes or a missing source file.
    public var activityIntervals: [ActivityInterval]
    public init(metadata: ParsedSession) {
        id = metadata.id; provider = metadata.provider; sourceID = metadata.sourceID; model = metadata.model
        startedAt = metadata.startedAt; endedAt = metadata.endedAt
        inputTokens = metadata.inputTokens; outputTokens = metadata.outputTokens; cachedTokens = metadata.cachedTokens
        sourcePath = metadata.sourcePath; activityIntervals = metadata.intervals
    }
    public func update(_ metadata: ParsedSession) {
        sourceID = metadata.sourceID
        model = metadata.model; startedAt = metadata.startedAt; endedAt = metadata.endedAt
        inputTokens = metadata.inputTokens; outputTokens = metadata.outputTokens; cachedTokens = metadata.cachedTokens
        sourcePath = metadata.sourcePath; activityIntervals = metadata.intervals
    }
}
