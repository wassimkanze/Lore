import Foundation

/// Build only the known local conversation route, never open URLs supplied by logs.
public enum SessionNavigation {
    public static func url(provider: String, sourceID: String?) -> URL? {
        switch provider {
        case "Codex": codexURL(provider: provider, sourceID: sourceID)
        case "Claude Code": claudeURL(provider: provider, sourceID: sourceID)
        default: nil
        }
    }
    public static func codexURL(provider: String, sourceID: String?) -> URL? {
        guard provider == "Codex", let sourceID, let id = UUID(uuidString: sourceID) else { return nil }
        return URL(string: "codex://threads/" + id.uuidString.lowercased())
    }
    public static func claudeURL(provider: String, sourceID: String?) -> URL? {
        guard provider == "Claude Code", let sourceID, let id = UUID(uuidString: sourceID) else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "resume"
        components.queryItems = [URLQueryItem(name: "session", value: id.uuidString.lowercased())]
        return components.url
    }
}
