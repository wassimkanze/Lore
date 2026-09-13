import Foundation
import OSLog
import CryptoKit

/// Supports the public Gemini CLI JSON and append-only JSONL session formats.
/// Only whitelisted metadata is decoded, including within checkpoints.
public struct GeminiSessionParser: Sendable {
    public init() {}
    public func parse(at url: URL, workingDirectory: String? = nil) throws -> ParsedSession? {
        var state = State()
        if url.pathExtension == "json" {
            let data = try SessionMetadataSupport.readBounded(url, limit: 32 * 1_024 * 1_024)
            state.consume(try JSONDecoder().decode(Record.self, from: data))
        } else {
            var malformed = 0
            try JSONLReader.read(url) { data in
                if let record = try? JSONDecoder().decode(Record.self, from: data) { state.consume(record) }
                else { malformed += 1 }
            }
            if malformed > 0 { Logger(subsystem: "app.lore.mac", category: "GeminiParser").debug("Skipped \(malformed) malformed metadata records") }
        }
        return state.finish(path: url.path, workingDirectory: workingDirectory)
    }
    private struct Metadata: Decodable {
        let sessionID: String?
        let projectHash: String?
        let start: String?
        let directories: [String]?
        let messages: [Message]?
        enum Keys: String, CodingKey { case sessionId, projectHash, startTime, directories, messages }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            sessionID = values.optionalString(.sessionId); projectHash = values.optionalString(.projectHash); start = values.optionalString(.startTime)
            directories = try? values.decode([String].self, forKey: .directories)
            if var array = try? values.nestedUnkeyedContainer(forKey: .messages) {
                var result: [Message] = []
                while !array.isAtEnd {
                    let child = try array.superDecoder()
                    if let message = try? Message(from: child) { result.append(message) }
                }
                messages = result
            } else { messages = nil }
        }
    }
    private struct Record: Decodable {
        let metadata: Metadata?
        let message: Message?
        let rewind: String?
        let isCheckpoint: Bool
        enum Keys: String, CodingKey { case set = "$set", rewind = "$rewindTo", sessionId, id }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            rewind = values.optionalString(.rewind)
            isCheckpoint = values.contains(.set)
            if isCheckpoint { metadata = try? values.decode(Metadata.self, forKey: .set) }
            else if values.contains(.sessionId) { metadata = try? Metadata(from: decoder) }
            else { metadata = nil }
            message = values.contains(.id) ? try? Message(from: decoder) : nil
        }
    }
    private struct Message: Decodable {
        let id: String
        let type: String
        let timestamp: Date?
        let model: String?
        var tokens = TokenCounters()
        enum Keys: String, CodingKey { case id, type, timestamp, model, tokens }
        enum UsageKeys: String, CodingKey { case input, output, cached, thoughts }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            id = try values.decode(String.self, forKey: .id)
            type = values.optionalString(.type) ?? "unknown"
            timestamp = MetadataDate.parse(values.optionalString(.timestamp)); model = values.optionalString(.model)
            if type == "gemini", let usage = try? values.nestedContainer(keyedBy: UsageKeys.self, forKey: .tokens) {
                tokens.input = usage.counter(.input)
                // Thoughts are generated output, separate from candidates in Gemini's format.
                tokens.output = SessionMetadataSupport.sum([usage.counter(.output), usage.counter(.thoughts)])
                tokens.cached = usage.counter(.cached)
            }
        }
    }
    private struct State {
        var id: String?, projectHash: String?, start: Date?
        var directories: [String] = []
        var messages: [String: Message] = [:]
        var order: [String] = []
        mutating func insert(_ message: Message) {
            guard !message.id.isEmpty else { return }
            if messages[message.id] == nil { order.append(message.id) }
            messages[message.id] = message
        }
        mutating func consume(_ record: Record) {
            if let rewind = record.rewind {
                let index = order.firstIndex(of: rewind) ?? 0
                for id in order[index...] { messages.removeValue(forKey: id) }
                order.removeSubrange(index...)
            }
            if let metadata = record.metadata {
                if let value = metadata.sessionID, !value.isEmpty { id = value }
                projectHash = metadata.projectHash ?? projectHash
                start = MetadataDate.parse(metadata.start) ?? start
                directories = metadata.directories ?? directories
                if let batch = metadata.messages {
                    if record.isCheckpoint { messages.removeAll(); order.removeAll() }
                    for message in batch { insert(message) }
                }
            }
            if let message = record.message { insert(message) }
        }
        func finish(path: String, workingDirectory: String?) -> ParsedSession? {
            let activity = order.compactMap { messages[$0] }.filter { $0.type == "user" || $0.type == "gemini" }
            let dates = activity.compactMap(\.timestamp)
            guard let id, let start = start ?? dates.min() else { return nil }
            // directories can contain /dir additions. Only use a directory whose hash matches the project.
            let verifiedDirectory = directories.first { value in
                guard SessionMetadataSupport.absolutePath(value) != nil, let projectHash else { return false }
                return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() == projectHash
            }
            let model = activity.filter { $0.model != nil && $0.type == "gemini" }.max {
                ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
            }?.model
            return ParsedSession(sourceID: id, provider: "Gemini CLI", model: model,
                                 workingDirectory: SessionMetadataSupport.absolutePath(workingDirectory) ?? verifiedDirectory,
                                 startedAt: min(start, dates.min() ?? start), endedAt: dates.max(),
                                 inputTokens: SessionMetadataSupport.sum(activity.map { $0.tokens.input }),
                                 outputTokens: SessionMetadataSupport.sum(activity.map { $0.tokens.output }),
                                 cachedTokens: SessionMetadataSupport.sum(activity.map { $0.tokens.cached }), sourcePath: path,
                                 intervals: SessionMetadataSupport.intervals(dates, fallback: start))
        }
    }
}
