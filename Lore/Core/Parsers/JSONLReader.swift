import Foundation

/// Bounded memory even for large logs and malformed, unbroken lines.
public enum JSONLReader {
    public static func read(_ url: URL, maximumLineBytes: Int = 8 * 1_024 * 1_024, consume: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        var discarding = false
        while let chunk = try handle.read(upToCount: 128 * 1_024), !chunk.isEmpty {
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 0x0A)
                let end = newline ?? chunk.endIndex
                if !discarding {
                    if pending.count + end - start <= maximumLineBytes { pending.append(chunk[start..<end]) }
                    else { pending.removeAll(keepingCapacity: true); discarding = true }
                }
                if let newline {
                    if !discarding && !pending.isEmpty { consume(pending) }
                    pending.removeAll(keepingCapacity: true); discarding = false
                    start = newline + 1
                } else { break }
            }
        }
        if !discarding && !pending.isEmpty { consume(pending) }
    }
}
