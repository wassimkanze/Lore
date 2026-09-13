import Foundation
import SwiftData

@Model public final class ActivityBlock {
    @Attribute(.unique) public var id: String
    public var project: Project?
    public var startedAt: Date
    public var endedAt: Date
    @Relationship(deleteRule: .nullify, inverse: \AISession.blocks) public var sessions: [AISession] = []
    @Relationship(deleteRule: .nullify) public var commits: [GitCommit] = []
    public init(id: String, project: Project?, start: Date, end: Date) {
        self.id = id; self.project = project; startedAt = start; endedAt = end
    }
    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}
