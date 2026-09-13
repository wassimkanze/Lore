import Foundation

public struct ClaudeCodeIntegration: AIProviderIntegration {
    public let provider = "Claude Code"
    public let directory: URL
    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")) { self.directory = directory }
    public func discoverSessions() throws -> [URL] {
        let root = directory.appendingPathComponent("projects")
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var files: [URL] = []
        for project in try LocalSessionDiscovery.directories(in: root) {
            files += (try? LocalSessionDiscovery.files(in: project, extensions: ["jsonl"])) ?? []
        }
        // Main session logs only: nested subagents may reuse their parent's sessionId.
        return files.sorted { $0.path < $1.path }
    }
    public func parseSession(at url: URL) throws -> ParsedSession? { try ClaudeCodeSessionParser().parse(at: url) }
}
