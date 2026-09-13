import Foundation

/// Lexical admission check happens before touching a path taken from an external log.
public struct RepositoryAccessPolicy: Sendable, Equatable {
    public let roots: [String]
    public let unrestricted: Bool
    public init(roots: [String], unrestricted: Bool = false) {
        self.roots = roots.filter { $0.hasPrefix("/") && !$0.contains("\0") }.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        self.unrestricted = unrestricted
    }
    public static let unrestrictedAccess = Self(roots: [], unrestricted: true)
    public func permits(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\0") else { return false }
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        return unrestricted || roots.contains { root in path == root || path.hasPrefix(root == "/" ? "/" : root + "/") }
    }
}

public struct FolderGrant: Codable, Identifiable, Sendable {
    public var id: UUID
    public var purpose: String
    public var path: String
    public var bookmark: Data
    public init(purpose: String, path: String, bookmark: Data) {
        id = UUID(); self.purpose = purpose; self.path = path; self.bookmark = bookmark
    }
}
