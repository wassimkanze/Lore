import Foundation

/// Task boundaries constrain estimates; older formats still use the inactivity rule.
struct ObservedActivity {
    enum Boundary { case observation, started, finished }
    struct Event { var date: Date; var boundary: Boundary }
    static func intervals(_ events: [Event], fallback: Date) -> [ActivityInterval] {
        var result: [ActivityInterval] = []
        var current: ActivityInterval?
        for (_, event) in events.enumerated().sorted(by: { $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date < $1.element.date }) {
            if event.boundary == .started {
                if let current { result.append(current) }
                current = ActivityInterval(start: event.date, end: event.date)
            } else if var active = current {
                if event.date.timeIntervalSince(active.end) <= ActivityPolicy.inactivityThreshold {
                    active.end = event.date; current = active
                } else {
                    result.append(active); current = ActivityInterval(start: event.date, end: event.date)
                }
            } else { current = ActivityInterval(start: event.date, end: event.date) }
            if event.boundary == .finished {
                if let current { result.append(current) }
                current = nil
            }
        }
        if let current { result.append(current) }
        return result.isEmpty ? [ActivityInterval(start: fallback, end: fallback)] : result
    }
}
