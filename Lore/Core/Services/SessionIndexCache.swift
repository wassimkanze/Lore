import Foundation
import Darwin

/// Change times and inode identity catch replacement, truncation and same-size rewrites.
struct SourceFingerprint: Codable, Equatable {
    var path: String
    var size: Int64?
    var inode: UInt64?
    var device: Int32?
    var modifiedSeconds: Int?
    var modifiedNanos: Int?
    var changedSeconds: Int?
    var changedNanos: Int?
    init(_ url: URL) {
        path = url.path
        var value = stat()
        guard stat(url.path, &value) == 0 else { return }
        size = value.st_size; inode = value.st_ino; device = value.st_dev
        modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
    }
}

/// A disposable cache of the same allowlisted metadata as the index, never JSONL content.
struct SessionIndexCache: Codable {
    static let version = 2 // Bump when parser behavior or metadata semantics change.
    var version = Self.version
    struct Entry: Codable {
        var fingerprints: [SourceFingerprint]
        var session: ParsedSession?
    }
    var entries: [String: Entry] = [:]
    static var defaultURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lore/session-index-v2.json")
    }
    static func load(_ url: URL?) -> Self {
        guard let url, let bytes = try? SessionMetadataSupport.readBounded(url, limit: 32 * 1024 * 1024),
              let value = try? JSONDecoder().decode(Self.self, from: bytes), value.version == version else { return Self() }
        return value
    }
    func save(_ url: URL?) throws {
        guard let url else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let bytes = try JSONEncoder().encode(self)
        guard bytes.count <= 32 * 1024 * 1024 else { return }
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
