import Foundation

public struct CodexIntegration: AIProviderIntegration {
    public let provider = "Codex"
    public let directory: URL
    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.directory = directory
    }
    public var isDetected: Bool { FileManager.default.fileExists(atPath: directory.path) }
    public func discoverSessions() throws -> [URL] {
        var files: [URL] = []
        for name in ["sessions", "archived_sessions"] {
            let root = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            // Enumerators do not follow symbolic-link directories. Only regular files are read.
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { files.append(url) }
            }
        }
        return files.sorted { $0.path < $1.path }
    }
    public func parseSession(at url: URL) throws -> ParsedSession? { try CodexSessionParser().parse(at: url) }
}
