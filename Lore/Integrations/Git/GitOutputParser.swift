import Foundation

public enum GitOutputParser {
    /// NUL-delimited headers and paths make tabs/newlines in filenames safe.
    public static func commits(_ output: String) -> [CommitMetadata] {
        let fields = output.components(separatedBy: "\0")
        var index = 0
        var result: [CommitMetadata] = []
        while index < fields.count {
            guard fields[index] == "LORE_COMMIT", index + 4 < fields.count else { index += 1; continue }
            let hash = fields[index + 1], author = fields[index + 2], timestamp = fields[index + 3], message = fields[index + 4]
            index += 5
            var additions = 0, deletions = 0, files = 0
            while index < fields.count && fields[index] != "LORE_COMMIT" {
                let stat = fields[index].trimmingCharacters(in: .newlines).split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                if stat.count == 3,
                   (Int(stat[0]) != nil || stat[0] == "-"), (Int(stat[1]) != nil || stat[1] == "-") {
                    files += 1; additions += max(0, Int(stat[0]) ?? 0); deletions += max(0, Int(stat[1]) ?? 0)
                }
                index += 1
            }
            guard (40...64).contains(hash.count), hash.allSatisfy(\.isHexDigit), let seconds = TimeInterval(timestamp) else { continue }
            result.append(CommitMetadata(hash: hash, author: author, message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                                         timestamp: Date(timeIntervalSince1970: seconds), additions: additions, deletions: deletions, filesChanged: files))
        }
        return result
    }
}
