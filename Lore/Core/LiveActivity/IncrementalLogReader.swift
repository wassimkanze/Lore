import Foundation

/// Reads only appended bytes. A partially written line is retained until its newline arrives.
public struct IncrementalLogReader: Sendable {
    private var offset: UInt64 = 0
    private var inode: UInt64?
    private var modifiedAt: Date?
    private var pending = Data()
    private var discarding = false
    public private(set) var didReset = false
    public init() {}
    public mutating func read(at url: URL, bootstrapLimit: Int = 2 * 1_024 * 1_024,
                              maximumRead: Int = 2 * 1_024 * 1_024, maximumLine: Int = 512 * 1_024) throws -> [Data] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let number = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let modified = attributes[.modificationDate] as? Date
        didReset = inode == nil || inode != number || size < offset || (size == offset && modified != modifiedAt)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var records: [Data] = []
        if didReset {
            pending.removeAll(); discarding = false
            offset = size > UInt64(bootstrapLimit) ? size - UInt64(bootstrapLimit) : 0
            if offset > 0 {
                // The first record often contains identity. Return it separately from the bounded tail.
                let head = try handle.read(upToCount: 512 * 1_024) ?? Data()
                if let newline = head.firstIndex(of: 10) { records.append(Data(head[..<newline])) }
                discarding = true
            }
        }
        inode = number; modifiedAt = modified
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: maximumRead) ?? Data()
        offset += UInt64(data.count)
        var start = data.startIndex
        while start < data.endIndex {
            let newline = data[start...].firstIndex(of: 10)
            let end = newline ?? data.endIndex
            if !discarding {
                if pending.count + end - start <= maximumLine { pending.append(data[start..<end]) }
                else { pending.removeAll(); discarding = true }
            }
            if let newline {
                if !discarding && !pending.isEmpty { records.append(pending) }
                pending.removeAll(keepingCapacity: true); discarding = false; start = newline + 1
            } else { break }
        }
        return records
    }
}
