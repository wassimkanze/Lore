import Foundation

public enum LivePhase: String, Sendable, Equatable {
    case working, needsInput, completed, stopped, uncertain
    public var label: String {
        switch self {
        case .working: "Working"
        case .needsInput: "Needs your attention"
        case .completed: "Task finished"
        case .stopped: "Task stopped"
        case .uncertain: "No recent signal"
        }
    }
}

public enum LiveAttentionReason: String, Sendable, Equatable {
    case question, planApproval
    public var label: String { self == .question ? "Awaiting your reply" : "Awaiting plan approval" }
}

public enum LiveActivityPolicy {
    public static let pollingInterval: TimeInterval = 2
    public static let discoveryInterval: TimeInterval = 10
    public static let completionVisibility: TimeInterval = 45
    public static let workingFreshness: TimeInterval = 5 * 60
    public static let quietVisibility: TimeInterval = 30 * 60
    public static let inputVisibility: TimeInterval = 24 * 60 * 60
}

public struct LiveSession: Sendable, Equatable, Identifiable {
    public var id: String
    public var provider: String
    public var sourceID: String?
    public var projectName: String?
    public var model: String?
    public var phase: LivePhase
    public var attentionReason: LiveAttentionReason?
    public var statusLabel: String { phase == .needsInput ? attentionReason?.label ?? phase.label : phase.label }
    public var startedAt: Date
    public var updatedAt: Date
    public init(id: String, provider: String, projectName: String? = nil, model: String? = nil,
                phase: LivePhase, startedAt: Date, updatedAt: Date, attentionReason: LiveAttentionReason? = nil, sourceID: String? = nil) {
        self.sourceID = sourceID
        self.id = id; self.provider = provider; self.projectName = projectName; self.model = model
        self.phase = phase; self.attentionReason = attentionReason; self.startedAt = startedAt; self.updatedAt = updatedAt
    }
}

public enum LiveSignal: Sendable, Equatable {
    case started, progress, waiting(String), resolved(String), completed, stopped
}

public struct LiveEvent: Sendable {
    public var sourceID: String?
    public var cwd: String?
    public var model: String?
    public var timestamp: Date?
    public var turnID: String?
    public var attentionReason: LiveAttentionReason?
    public var signals: [LiveSignal]
    public init(sourceID: String? = nil, cwd: String? = nil, model: String? = nil, timestamp: Date? = nil,
                turnID: String? = nil, signals: [LiveSignal] = [], attentionReason: LiveAttentionReason? = nil) {
        self.sourceID = sourceID; self.cwd = cwd; self.model = model; self.timestamp = timestamp
        self.turnID = turnID; self.signals = signals; self.attentionReason = attentionReason
    }
}

/// A transient state machine. No task state, question text or conversation is stored in SwiftData.
public struct LiveSessionState: Sendable {
    public let provider: String
    private let fallbackID: String
    private var sourceID: String?
    private var project: String?
    private var model: String?
    private var phase: LivePhase?
    private var startedAt: Date?
    private var updatedAt: Date?
    private var terminalAt: Date?
    private var waitingAt: Date?
    private var turnID: String?
    private var pending: Set<String> = []
    private var waitingReasons: [String: LiveAttentionReason] = [:]
    public init(provider: String, sourcePath: String) { self.provider = provider; fallbackID = sourcePath }
    public mutating func consume(_ event: LiveEvent) {
        if let id = event.sourceID, !id.isEmpty { sourceID = id }
        if let path = SessionMetadataSupport.absolutePath(event.cwd) { project = URL(fileURLWithPath: path).lastPathComponent }
        if let model = event.model, !model.isEmpty, !model.hasPrefix("<") { self.model = model }
        guard let date = event.timestamp else { return }
        // Replayed/out-of-order terminal events must not overwrite a later turn.
        if let updatedAt, date < updatedAt { return }
        for signal in event.signals {
            switch signal {
            case .started:
                phase = .working; startedAt = date; terminalAt = nil; waitingAt = nil
                turnID = event.turnID ?? turnID; pending.removeAll(); waitingReasons.removeAll()
            case .progress:
                if phase == .completed || phase == .stopped { continue }
                if phase == nil { phase = .working; startedAt = date; turnID = event.turnID }
            case .waiting(let requestID):
                if phase == .completed || phase == .stopped { continue }
                pending.insert(requestID); waitingReasons[requestID] = event.attentionReason; waitingAt = date; phase = .needsInput
                startedAt = startedAt ?? date
            case .resolved(let requestID):
                pending.remove(requestID); waitingReasons.removeValue(forKey: requestID)
                if pending.isEmpty && phase == .needsInput { phase = .working; waitingAt = nil }
            case .completed, .stopped:
                if let expected = turnID, let actual = event.turnID, expected != actual { continue }
                phase = signal == .completed ? .completed : .stopped
                terminalAt = date; pending.removeAll(); waitingReasons.removeAll(); waitingAt = nil; startedAt = startedAt ?? date
            }
            updatedAt = date
        }
    }
    public func snapshot(at now: Date) -> LiveSession? {
        guard var phase, let updatedAt, let startedAt else { return nil }
        let age = max(0, now.timeIntervalSince(updatedAt))
        // Future-dated/corrupt records do not create permanent badges.
        guard updatedAt.timeIntervalSince(now) <= 60 else { return nil }
        switch phase {
        case .completed, .stopped:
            guard now.timeIntervalSince(terminalAt ?? updatedAt) <= LiveActivityPolicy.completionVisibility else { return nil }
        case .needsInput:
            guard now.timeIntervalSince(waitingAt ?? updatedAt) <= LiveActivityPolicy.inputVisibility else { return nil }
        case .working, .uncertain:
            guard age <= LiveActivityPolicy.quietVisibility else { return nil }
            if age > LiveActivityPolicy.workingFreshness { phase = .uncertain }
        }
        return LiveSession(id: StableID.session(provider: provider, sourceID: sourceID ?? fallbackID), provider: provider,
                           projectName: project, model: model, phase: phase, startedAt: startedAt, updatedAt: updatedAt,
                           attentionReason: phase == .needsInput ? (waitingReasons.values.contains(.planApproval) ? .planApproval : waitingReasons.values.first) : nil, sourceID: sourceID)
    }
}

public enum NotchSide: Sendable { case left, right }
