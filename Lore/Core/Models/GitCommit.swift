import Foundation
import SwiftData

@Model public final class GitCommit {
    @Attribute(.unique) public var id: String
    // "hash" is reserved by NSObject/Core Data. Keep the domain name as a computed accessor.
    public var commitHash: String
    public var hash: String { commitHash }
    public var project: Project?
    public var author: String
    public var message: String
    public var timestamp: Date
    public var additions: Int
    public var deletions: Int
    public var filesChanged: Int
    public init(metadata: CommitMetadata, project: Project) {
        id = StableID.commit(projectID: project.id, hash: metadata.hash)
        commitHash = metadata.hash; self.project = project; author = metadata.author
        message = metadata.message; timestamp = metadata.timestamp
        additions = metadata.additions; deletions = metadata.deletions; filesChanged = metadata.filesChanged
    }
}
