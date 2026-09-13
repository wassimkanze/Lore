import Foundation
import SwiftData

@Model public final class Project {
    @Attribute(.unique) public var id: String
    public var name: String
    public var path: String
    public var gitRemote: String?
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    @Relationship(deleteRule: .cascade, inverse: \AISession.project) public var sessions: [AISession] = []
    @Relationship(deleteRule: .cascade, inverse: \GitCommit.project) public var commits: [GitCommit] = []
    @Relationship(deleteRule: .cascade, inverse: \ActivityBlock.project) public var blocks: [ActivityBlock] = []

    public init(path: String, at date: Date) {
        self.id = StableID.project(path: path); self.path = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.firstSeenAt = date; self.lastSeenAt = date
    }
}
