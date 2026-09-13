import Foundation

public struct GeminiCLIIntegration: AIProviderIntegration {
    public let provider = "Gemini CLI"
    public let directory: URL
    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini")) { self.directory = directory }
    public var diagnosticNote: String? {
        guard !isDetected else { return nil }
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.google.GeminiMacOS")
        if FileManager.default.fileExists(atPath: support.path) {
            return "Gemini desktop detected. Its account/settings stores are not session history; no CLI history found."
        }
        return "No local Gemini CLI history found."
    }
    public func discoverSessions() throws -> [URL] {
        let root = directory.appendingPathComponent("tmp")
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var files: [URL] = []
        for project in try LocalSessionDiscovery.directories(in: root) {
            files += ((try? LocalSessionDiscovery.files(in: project.appendingPathComponent("chats"), extensions: ["json", "jsonl"])) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("session-") }
        }
        return files.sorted { $0.path < $1.path }
    }
    public func cacheDependencies(at url: URL) -> [URL] {
        [url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".project_root"), directory.appendingPathComponent("projects.json")]
    }
    public func parseSession(at url: URL) throws -> ParsedSession? {
        let projectDirectory = url.deletingLastPathComponent().deletingLastPathComponent()
        var cwd: String?
        let marker = projectDirectory.appendingPathComponent(".project_root")
        if let data = try? SessionMetadataSupport.readBounded(marker, limit: 16_384), let value = String(data: data, encoding: .utf8) {
            cwd = SessionMetadataSupport.absolutePath(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if cwd == nil, let data = try? SessionMetadataSupport.readBounded(directory.appendingPathComponent("projects.json"), limit: 4 * 1_024 * 1_024),
           let registry = try? JSONDecoder().decode(Registry.self, from: data) {
            let candidates = registry.projects.filter { $0.value == projectDirectory.lastPathComponent }.keys
            if candidates.count == 1 { cwd = SessionMetadataSupport.absolutePath(candidates.first) }
        }
        return try GeminiSessionParser().parse(at: url, workingDirectory: cwd)
    }
    private struct Registry: Decodable { let projects: [String: String] }
}
