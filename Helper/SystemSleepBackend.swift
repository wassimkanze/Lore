import Foundation
import Darwin

/// Root-only, fixed operations. No arguments or filesystem paths are supplied by clients.
final class SystemSleepBackend: ClosedLidBackend {
    private let directory = URL(fileURLWithPath: "/Library/Application Support/LorePowerHelper", isDirectory: true)
    private var journal: URL { directory.appendingPathComponent("recovery.json") }
    init() throws {
        var info = stat()
        if lstat(directory.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == 0, (info.st_mode & 0o077) == 0 else { throw CocoaError(.fileReadNoPermission) }
        } else {
            guard errno == ENOENT, mkdir(directory.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        }
    }
    func isSleepDisabled() throws -> Bool {
        let text = try run(["-g"])
        guard text.contains("System-wide power settings:") else { throw CocoaError(.fileReadCorruptFile) }
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.first == "SleepDisabled" {
                guard parts.count >= 2, ["0", "1"].contains(parts[1]) else { throw CocoaError(.fileReadCorruptFile) }
                return parts[1] == "1"
            }
        }
        return false // pmset omits unset system-wide preferences.
    }
    func setSleepDisabled(_ disabled: Bool) throws { _ = try run(["-a", "disablesleep", disabled ? "1" : "0"]) }
    func hasRecoveryRecord() throws -> Bool {
        var info = stat()
        if lstat(journal.path, &info) != 0 {
            if errno == ENOENT { return false }
            throw CocoaError(.fileReadNoPermission)
        }
        guard info.st_uid == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1, info.st_size < 1024 else { throw CocoaError(.fileReadNoPermission) }
        let data = try Data(contentsOf: journal)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Bool], object["ownsDisable"] == true else { throw CocoaError(.fileReadCorruptFile) }
        return true
    }
    func writeRecoveryRecord() throws { try Data("{\"ownsDisable\":true}".utf8).write(to: journal, options: .atomic) }
    func clearRecoveryRecord() throws { if try hasRecoveryRecord() { try FileManager.default.removeItem(at: journal) } }
    private func run(_ arguments: [String]) throws -> String {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeout.cancel()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return String(decoding: data, as: UTF8.self)
    }
}
