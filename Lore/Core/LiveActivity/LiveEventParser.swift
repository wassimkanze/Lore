import Foundation

/// Purpose-specific decoding: names, IDs and lifecycle flags only. Text, tool arguments and outputs are skipped.
public enum LiveEventParser {
    public static func parse(_ data: Data, provider: String) -> LiveEvent? {
        switch provider {
        case "Codex": return (try? JSONDecoder().decode(CodexEvent.self, from: data))?.event
        case "Claude Code": return (try? JSONDecoder().decode(ClaudeEvent.self, from: data))?.event
        case "Gemini CLI": return (try? JSONDecoder().decode(GeminiEvent.self, from: data))?.event
        default: return nil
        }
    }
    private struct CodexEvent: Decodable {
        var event = LiveEvent()
        enum Keys: String, CodingKey { case type, timestamp, payload }
        enum Payload: String, CodingKey { case type, id, session_id, cwd, model, turn_id, name, call_id, role }
        init(from decoder: any Decoder) throws {
            let root = try decoder.container(keyedBy: Keys.self)
            let type = root.optionalString(.type)
            event.timestamp = MetadataDate.parse(root.optionalString(.timestamp))
            guard let payload = try? root.nestedContainer(keyedBy: Payload.self, forKey: .payload) else { return }
            event.turnID = payload.optionalString(.turn_id)
            switch type {
            case "session_meta":
                event.sourceID = payload.optionalString(.id) ?? payload.optionalString(.session_id)
                event.cwd = payload.optionalString(.cwd)
            case "turn_context":
                event.cwd = payload.optionalString(.cwd); event.model = payload.optionalString(.model)
                event.signals = [.progress]
            case "event_msg":
                switch payload.optionalString(.type) {
                case "task_started": event.signals = [.started]
                case "task_complete": event.signals = [.completed]
                case "turn_aborted": event.signals = [.stopped]
                case "token_count", "item_completed": event.signals = [.progress]
                default: break
                }
            case "token_usage_record": event.signals = [.progress]
            case "response_item":
                switch payload.optionalString(.type) {
                case "function_call", "custom_tool_call":
                    event.signals = [.progress]
                    let name = payload.optionalString(.name)?.split(separator: ".").last.map(String.init)
                    if let call = payload.optionalString(.call_id), let name {
                        if name == "request_user_input" { event.signals.append(.waiting(call)); event.attentionReason = .question }
                        if name == "request_user_input_async" { event.signals.append(.waiting("async:" + call)); event.attentionReason = .question }
                    }
                case "function_call_output", "custom_tool_call_output":
                    if let id = payload.optionalString(.call_id) { event.signals = [.resolved(id), .progress] }
                case "message":
                    if payload.optionalString(.role) == "user" { event.signals = [.started] }
                    else { event.signals = [.progress] }
                case "reasoning": event.signals = [.progress]
                default: break
                }
            default: break
            }
        }
    }
    private struct ClaudePart: Decodable {
        let type: String?
        let name: String?
        let id: String?
        let resultID: String?
        enum Keys: String, CodingKey { case type, name, id, tool_use_id }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            type = values.optionalString(.type); name = values.optionalString(.name)
            id = values.optionalString(.id); resultID = values.optionalString(.tool_use_id)
        }
    }
    private struct ClaudeEvent: Decodable {
        var event = LiveEvent()
        enum Keys: String, CodingKey { case type, subtype, sessionId, cwd, timestamp, message, preventedContinuation }
        enum Message: String, CodingKey { case model, stop_reason, content }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            event.sourceID = values.optionalString(.sessionId); event.cwd = values.optionalString(.cwd)
            event.timestamp = MetadataDate.parse(values.optionalString(.timestamp))
            let type = values.optionalString(.type)
            if type == "system", values.optionalString(.subtype) == "stop_hook_summary" {
                if (try? values.decode(Bool.self, forKey: .preventedContinuation)) == false { event.signals = [.completed] }
                return
            }
            guard type == "user" || type == "assistant", let message = try? values.nestedContainer(keyedBy: Message.self, forKey: .message) else { return }
            event.model = message.optionalString(.model)
            let parts = (try? message.decode([ClaudePart].self, forKey: .content)) ?? []
            if type == "user" {
                let results = parts.compactMap(\.resultID)
                event.signals = results.isEmpty ? [.started] : results.map { .resolved($0) } + [.progress]
            } else {
                event.signals = [.progress]
                for part in parts where part.type == "tool_use" && ["AskUserQuestion", "ExitPlanMode"].contains(part.name ?? "") {
                    if let id = part.id { event.signals.append(.waiting(id)); event.attentionReason = part.name == "ExitPlanMode" ? .planApproval : .question }
                }
                if message.optionalString(.stop_reason) == "end_turn" { event.signals.append(.completed) }
            }
        }
    }
    private struct GeminiEvent: Decodable {
        var event = LiveEvent()
        enum Keys: String, CodingKey { case sessionId, type, timestamp, model, toolCalls }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            event.sourceID = values.optionalString(.sessionId); event.model = values.optionalString(.model)
            event.timestamp = MetadataDate.parse(values.optionalString(.timestamp))
            switch values.optionalString(.type) {
            case "user": event.signals = [.started]
            case "gemini": event.signals = [.progress]
            default: break
            }
            // Gemini recordings expose message activity, not a reliable turn-completion marker.
            // No checkmark or approval state is inferred from silence or tool output.
        }
    }
}
