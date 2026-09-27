import Foundation

/// Reads only Pi's per-project session logs, never credentials, settings or extension state.
public struct PiIntegration: AIProviderIntegration {
    public let provider = "Pi"
    public let directory: URL
    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi")) { self.directory = directory }
    public func discoverSessions() throws -> [URL] {
        let root = directory.appendingPathComponent("agent/sessions")
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var files: [URL] = []
        for project in try LocalSessionDiscovery.directories(in: root) {
            files += (try? LocalSessionDiscovery.files(in: project, extensions: ["jsonl"])) ?? []
        }
        return files.sorted { $0.path < $1.path }
    }
    public func parseSession(at url: URL) throws -> ParsedSession? { try PiSessionParser().parse(at: url) }
}

public struct PiSessionParser: Sendable {
    public init() {}
    public func parse(at url: URL) throws -> ParsedSession? {
        var id: String?, cwd: String?, model: String?
        var dates: [Date] = []
        var input: [Int?] = [], output: [Int?] = [], cached: [Int?] = []
        try JSONLReader.read(url) { data in
            guard let record = try? JSONDecoder().decode(Record.self, from: data) else { return }
            if record.type == "session" {
                // The header, not the filename or a branch entry, identifies the session.
                if id == nil { id = record.id; cwd = SessionMetadataSupport.absolutePath(record.cwd) }
                if let date = MetadataDate.parse(record.timestamp) { dates.append(date) }
                return
            }
            guard id != nil else { return }
            guard record.type == "message" || ["usage", "compaction", "branch_summary"].contains(record.type) else { return }
            guard let date = MetadataDate.parse(record.timestamp) else { return }
            // Only conversation and model-usage records are activity observations.
            if record.type == "message", !["user", "assistant", "toolResult"].contains(record.message?.role ?? "") { return }
            dates.append(date)
            if record.type == "message", record.message?.role == "assistant" {
                if let name = record.message?.model, !name.isEmpty, !name.hasPrefix("<") { model = name }
            } else if record.type == "usage", let name = record.model, !name.isEmpty { model = name }
            let usage = record.type == "message" ? record.message?.usage : record.usage
            if let usage {
                // Pi reports uncached input separately from reads and writes; cached is reads only.
                input.append(SessionMetadataSupport.sum([usage.input, usage.cacheRead, usage.cacheWrite]))
                output.append(usage.output)
                cached.append(usage.cacheRead)
            }
        }
        guard let id, !id.isEmpty, let start = dates.min() else { return nil }
        return ParsedSession(sourceID: id, provider: "Pi", model: model, workingDirectory: cwd,
                             startedAt: start, endedAt: dates.max(), inputTokens: SessionMetadataSupport.sum(input),
                             outputTokens: SessionMetadataSupport.sum(output), cachedTokens: SessionMetadataSupport.sum(cached),
                             sourcePath: url.path, intervals: SessionMetadataSupport.intervals(dates, fallback: start))
    }
    private struct Record: Decodable {
        let type: String
        let id: String?
        let cwd: String?
        let timestamp: String?
        let model: String?
        let usage: Usage?
        let message: Message?
        enum Keys: String, CodingKey { case type, id, cwd, timestamp, model, usage, message }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            type = values.optionalString(.type) ?? ""
            id = values.optionalString(.id); cwd = values.optionalString(.cwd)
            timestamp = values.optionalString(.timestamp); model = values.optionalString(.model)
            usage = try? values.decode(Usage.self, forKey: .usage)
            message = type == "message" ? try? values.decode(Message.self, forKey: .message) : nil
        }
    }
    private struct Message: Decodable {
        let role: String?
        let model: String?
        let usage: Usage?
    }
    private struct Usage: Decodable {
        let input: Int?
        let output: Int?
        let cacheRead: Int?
        let cacheWrite: Int?
        enum Keys: String, CodingKey { case input, output, cacheRead, cacheWrite }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            input = values.counter(.input); output = values.counter(.output)
            cacheRead = values.counter(.cacheRead); cacheWrite = values.counter(.cacheWrite)
        }
    }
}
