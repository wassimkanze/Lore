import Foundation
import OSLog

public struct CodexSessionParser: Sendable {
    private static let logger = Logger(subsystem: "app.lore.mac", category: "CodexParser")
    public init() {}
    public func parse(at url: URL) throws -> ParsedSession? {
        var state = State()
        let decoder = JSONDecoder()
        try JSONLReader.read(url) { data in
            // Decodable's allowlist skips prompts, responses, tool arguments, and instructions.
            guard let record = try? decoder.decode(Record.self, from: data) else { state.malformed += 1; return }
            state.consume(record)
        }
        if state.malformed > 0 {
            Self.logger.debug("Skipped \(state.malformed) malformed metadata records")
        }
        return state.finish(path: url.path)
    }

    private struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cached_input_tokens: Int?
        enum Keys: String, CodingKey { case input_tokens, output_tokens, cached_input_tokens }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            input_tokens = try? values.decode(Int.self, forKey: .input_tokens)
            output_tokens = try? values.decode(Int.self, forKey: .output_tokens)
            cached_input_tokens = try? values.decode(Int.self, forKey: .cached_input_tokens)
        }
    }
    private struct UsageInfo: Decodable { let total_token_usage: Usage? }
    private struct Record: Decodable {
        let timestamp: String?
        let type: String
        var id: String?
        var cwd: String?
        var model: String?
        var start: String?
        var usage: Usage?
        var activity = false
        var boundary = ObservedActivity.Boundary.observation
        enum Keys: String, CodingKey { case timestamp, type, payload }
        enum PayloadKeys: String, CodingKey { case id, session_id, cwd, model, timestamp, type, info, thread_token_usage }
        init(from decoder: any Decoder) throws {
            let root = try decoder.container(keyedBy: Keys.self)
            timestamp = try? root.decode(String.self, forKey: .timestamp)
            type = (try? root.decode(String.self, forKey: .type)) ?? "unknown"
            guard ["session_meta", "turn_context", "token_usage_record", "event_msg"].contains(type),
                  let payload = try? root.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload) else { return }
            switch type {
            case "session_meta":
                id = (try? payload.decode(String.self, forKey: .id)) ?? (try? payload.decode(String.self, forKey: .session_id))
                cwd = try? payload.decode(String.self, forKey: .cwd)
                start = try? payload.decode(String.self, forKey: .timestamp)
                model = try? payload.decode(String.self, forKey: .model)
            case "turn_context":
                cwd = try? payload.decode(String.self, forKey: .cwd)
                model = try? payload.decode(String.self, forKey: .model)
                activity = true
            case "token_usage_record":
                usage = try? payload.decode(Usage.self, forKey: .thread_token_usage)
                activity = true
            case "event_msg":
                let subtype = try? payload.decode(String.self, forKey: .type)
                activity = ["task_started", "task_complete", "token_count", "item_completed"].contains(subtype ?? "")
                if subtype == "task_started" { boundary = .started }
                if subtype == "task_complete" || subtype == "task_interrupted" { boundary = .finished; activity = true }
                if subtype == "token_count" { usage = (try? payload.decode(UsageInfo.self, forKey: .info))?.total_token_usage }
            default: break
            }
        }
    }

    private struct State {
        var sourceID: String?
        var cwd: String?
        var model: String?
        var start: Date?
        var dates: [Date] = []
        var events: [ObservedActivity.Event] = []
        var input: Int?
        var output: Int?
        var cached: Int?
        var malformed = 0
        mutating func consume(_ record: Record) {
            if record.type == "session_meta" {
                if let id = record.id, !id.isEmpty { sourceID = sourceID ?? id }
                start = start ?? MetadataDate.parse(record.start) ?? MetadataDate.parse(record.timestamp)
            }
            if let path = record.cwd, path.hasPrefix("/"), !path.contains("\0") { cwd = cwd ?? path }
            if let name = record.model, !name.isEmpty { model = name }
            if record.activity, let date = MetadataDate.parse(record.timestamp) { dates.append(date); events.append(.init(date: date, boundary: record.boundary)) }
            func counter(_ old: Int?, _ new: Int?) -> Int? {
                guard let new, new >= 0 else { return old }
                return max(old ?? 0, new)
            }
            input = counter(input, record.usage?.input_tokens)
            output = counter(output, record.usage?.output_tokens)
            cached = counter(cached, record.usage?.cached_input_tokens)
        }
        func finish(path: String) -> ParsedSession? {
            guard let sourceID, let start = start ?? dates.min() else { return nil }
            let ordered = dates.sorted()
            let intervals = ObservedActivity.intervals(events, fallback: start)
            return ParsedSession(sourceID: sourceID, provider: "Codex", model: model, workingDirectory: cwd,
                                 startedAt: min(start, ordered.first ?? start), endedAt: ordered.last,
                                 inputTokens: input, outputTokens: output, cachedTokens: cached,
                                 sourcePath: path, intervals: intervals)
        }
    }
}
