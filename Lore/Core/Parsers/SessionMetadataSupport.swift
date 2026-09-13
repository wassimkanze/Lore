import Foundation

/// Shared metadata-only primitives; no conversation-bearing keys belong here.
enum SessionMetadataSupport {
    static func absolutePath(_ value: String?) -> String? {
        guard let value, value.hasPrefix("/"), !value.contains("\0"), !value.contains("\n") else { return nil }
        return value
    }
    static func intervals(_ dates: [Date], fallback: Date) -> [ActivityInterval] {
        var intervals: [ActivityInterval] = []
        for date in dates.sorted() {
            if let last = intervals.last, date.timeIntervalSince(last.end) <= ActivityPolicy.inactivityThreshold {
                intervals[intervals.count - 1].end = max(last.end, date)
            } else { intervals.append(ActivityInterval(start: date, end: date)) }
        }
        return intervals.isEmpty ? [ActivityInterval(start: fallback, end: fallback)] : intervals
    }
    static func sum(_ values: [Int?]) -> Int? {
        let available = values.compactMap { $0 }.filter { $0 >= 0 }
        guard !available.isEmpty else { return nil }
        var total = 0
        for value in available {
            let next = total.addingReportingOverflow(value)
            guard !next.overflow else { return nil }
            total = next.partialValue
        }
        return total
    }
    static func readBounded(_ url: URL, limit: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
}

extension KeyedDecodingContainer {
    func optionalString(_ key: Key) -> String? { try? decode(String.self, forKey: key) }
    func counter(_ key: Key) -> Int? {
        guard let value = try? decode(Int.self, forKey: key), value >= 0 else { return nil }
        return value
    }
}

struct TokenCounters {
    var input: Int?
    var output: Int?
    var cached: Int?
    func merging(_ other: Self) -> Self {
        func greatest(_ a: Int?, _ b: Int?) -> Int? {
            if let a, let b { return max(a, b) }
            return a ?? b
        }
        return Self(input: greatest(input, other.input), output: greatest(output, other.output), cached: greatest(cached, other.cached))
    }
}
