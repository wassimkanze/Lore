import Foundation

public enum GitError: Error { case invalidPath, failed(Int32), timedOut }

/// All entry points are synchronous by design and invoked by the background indexing actor.
/// The argument list is private: callers cannot supply arbitrary Git commands.
public struct GitService: Sendable {
    public init() {}
    public func repository(at path: String) throws -> RepositoryMetadata {
        guard path.hasPrefix("/"), !path.contains("\0"), FileManager.default.fileExists(atPath: path) else { throw GitError.invalidPath }
        let root = try run(at: path, arguments: ["rev-parse", "--show-toplevel"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { throw GitError.invalidPath }
        let canonical = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
        let branch = try? run(at: canonical, arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawRemote = try? run(at: canonical, arguments: ["remote", "get-url", "origin"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return RepositoryMetadata(root: canonical, branch: branch, remote: Self.sanitizeRemote(rawRemote))
    }
    public func commits(at root: String, since: Date, until: Date) throws -> [CommitMetadata] {
        // Unborn repositories are valid and have no history.
        if (try? run(at: root, arguments: ["rev-parse", "--verify", "HEAD"])) == nil { return [] }
        let output = try run(at: root, arguments: [
            "log", "--no-show-signature", "--no-ext-diff", "--no-textconv", "--no-renames", "--numstat", "-z",
            "--format=%x00LORE_COMMIT%x00%H%x00%an%x00%ct%x00%B", "--since=@\(Int(since.timeIntervalSince1970))",
            "--until=@\(Int(until.timeIntervalSince1970))", "HEAD", "--"
        ])
        return GitOutputParser.commits(output)
    }
    public static func sanitizeRemote(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if var url = URLComponents(string: value), url.scheme != nil, url.host != nil {
            url.user = nil; url.password = nil; url.query = nil; url.fragment = nil
            return url.string
        }
        // Git's scp-style SSH syntax; remove the username as well.
        if let at = value.firstIndex(of: "@") { return String(value[value.index(after: at)...]) }
        return value
    }
    private func run(at path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", "-C", path] + arguments
        // Inherit no Git configuration overrides, credentials or askpass programs from Lore's environment.
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                               "LC_ALL": "C", "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0", "GIT_PAGER": "cat"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else { throw GitError.failed(process.terminationStatus) }
        return String(decoding: data, as: UTF8.self)
    }
}
