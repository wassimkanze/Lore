import Foundation

public struct ActivitySeed: Sendable {
    public var sessionID: String
    public var projectID: String
    public var interval: ActivityInterval
    public init(sessionID: String, projectID: String, interval: ActivityInterval) {
        self.sessionID = sessionID; self.projectID = projectID; self.interval = interval
    }
}
public struct GroupedActivity: Sendable, Equatable {
    public var id: String { StableID.make("activity", projectID, String(start.timeIntervalSince1970)) }
    public var projectID: String
    public var start: Date
    public var end: Date
    public var sessionIDs: [String]
}
public struct ActivityGroupingService: Sendable {
    public let inactivityThreshold: TimeInterval
    public init(inactivityThreshold: TimeInterval = ActivityPolicy.inactivityThreshold) { self.inactivityThreshold = max(0, inactivityThreshold) }
    public func group(_ seeds: [ActivitySeed]) -> [GroupedActivity] {
        var result: [GroupedActivity] = []
        for (project, seeds) in Dictionary(grouping: seeds, by: \.projectID) {
            var current: GroupedActivity?
            for seed in seeds.sorted(by: { ($0.interval.start, $0.sessionID) < ($1.interval.start, $1.sessionID) }) {
                if var block = current, seed.interval.start.timeIntervalSince(block.end) <= inactivityThreshold {
                    block.end = max(block.end, seed.interval.end)
                    block.sessionIDs = Array(Set(block.sessionIDs + [seed.sessionID])).sorted()
                    current = block
                } else {
                    if let current { result.append(current) }
                    current = GroupedActivity(projectID: project, start: seed.interval.start, end: seed.interval.end, sessionIDs: [seed.sessionID])
                }
            }
            if let current { result.append(current) }
        }
        return result.sorted { ($0.start, $0.projectID) < ($1.start, $1.projectID) }
    }
    /// Union across projects avoids double-counting concurrent agent work.
    public static func duration(of intervals: [ActivityInterval], within range: DateInterval? = nil) -> TimeInterval {
        let clipped = intervals.compactMap { interval -> ActivityInterval? in
            let start = max(interval.start, range?.start ?? interval.start)
            let end = min(interval.end, range?.end ?? interval.end)
            return end >= start ? ActivityInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: ActivityInterval?
        for interval in clipped {
            if let previous = current, interval.start <= previous.end { current?.end = max(previous.end, interval.end) }
            else {
                if let current { total += current.end.timeIntervalSince(current.start) }
                current = interval
            }
        }
        if let current { total += current.end.timeIntervalSince(current.start) }
        return total
    }
}
