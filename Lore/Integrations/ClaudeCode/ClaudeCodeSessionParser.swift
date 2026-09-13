import Foundation
import OSLog

public struct ClaudeCodeSessionParser: Sendable {
    public init() {}
    public func parse(at url: URL) throws -> ParsedSession? {
        var sessionID: String?, cwd: String?, model: String?
        var modelDate = Date.distantPast
        var dates: [Date] = []
        var usage: [String: TokenCounters] = [:]
        var malformed = 0
        try JSONLReader.read(url) { data in
            guard let record = try? JSONDecoder().decode(Record.self, from: data) else { malformed += 1; return }
            guard ["user", "assistant", "system"].contains(record.type) else { return }
            if let id = record.sessionID, !id.isEmpty {
                if let sessionID, sessionID != id { return }
                sessionID = id
            }
            cwd = cwd ?? SessionMetadataSupport.absolutePath(record.cwd)
            if let date = MetadataDate.parse(record.timestamp) { dates.append(date) }
            guard record.type == "assistant", let message = record.message else { return }
            let date = MetadataDate.parse(record.timestamp) ?? .distantPast
            if let name = message.model, !name.isEmpty, !name.hasPrefix("<"), date >= modelDate { model = name; modelDate = date }
            // A response can be logged once per content block. Count it once by message ID.
            guard let id = message.id ?? record.uuid, !id.isEmpty else { return }
            usage[id] = (usage[id] ?? TokenCounters()).merging(message.tokens)
        }
        if malformed > 0 { Logger(subsystem: "app.lore.mac", category: "ClaudeParser").debug("Skipped \(malformed) malformed metadata records") }
        guard let sessionID, let start = dates.min() else { return nil }
        return ParsedSession(sourceID: sessionID, provider: "Claude Code", model: model, workingDirectory: cwd,
                             startedAt: start, endedAt: dates.max(), inputTokens: SessionMetadataSupport.sum(usage.values.map(\.input)),
                             outputTokens: SessionMetadataSupport.sum(usage.values.map(\.output)), cachedTokens: SessionMetadataSupport.sum(usage.values.map(\.cached)),
                             sourcePath: url.path, intervals: SessionMetadataSupport.intervals(dates, fallback: start))
    }
    private struct Record: Decodable {
        let type: String
        let sessionID: String?
        let cwd: String?
        let timestamp: String?
        let uuid: String?
        let message: Message?
        enum Keys: String, CodingKey { case type, sessionId, cwd, timestamp, uuid, message }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            type = values.optionalString(.type) ?? "unknown"
            sessionID = values.optionalString(.sessionId); cwd = values.optionalString(.cwd)
            timestamp = values.optionalString(.timestamp); uuid = values.optionalString(.uuid)
            message = type == "assistant" ? try? values.decode(Message.self, forKey: .message) : nil
        }
    }
    private struct Message: Decodable {
        let id: String?
        let model: String?
        var tokens = TokenCounters()
        enum Keys: String, CodingKey { case id, model, usage }
        enum UsageKeys: String, CodingKey { case input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            id = values.optionalString(.id); model = values.optionalString(.model)
            if let usage = try? values.nestedContainer(keyedBy: UsageKeys.self, forKey: .usage) {
                // Anthropic reports cache reads/writes separately from uncached input.
                tokens.input = SessionMetadataSupport.sum([usage.counter(.input_tokens), usage.counter(.cache_read_input_tokens), usage.counter(.cache_creation_input_tokens)])
                tokens.output = usage.counter(.output_tokens)
                tokens.cached = usage.counter(.cache_read_input_tokens)
            }
        }
    }
}
