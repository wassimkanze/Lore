import Foundation

public protocol AIProviderIntegration: Sendable {
    var provider: String { get }
    var directory: URL { get }
    var isDetected: Bool { get }
    var diagnosticNote: String? { get }
    func discoverSessions() throws -> [URL]
    func parseSession(at url: URL) throws -> ParsedSession?
    func cacheDependencies(at url: URL) -> [URL]
}

extension AIProviderIntegration {
    public var isDetected: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    public var diagnosticNote: String? { nil }
    public func cacheDependencies(at url: URL) -> [URL] { [] }
}

public enum ProviderIntegrations {
    public static func defaults() -> [any AIProviderIntegration] {
        [CodexIntegration(), ClaudeCodeIntegration(), GeminiCLIIntegration()]
    }
}
