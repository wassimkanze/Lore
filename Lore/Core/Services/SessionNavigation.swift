import Foundation

/// Build only the known local conversation route, never open URLs supplied by logs.
public enum SessionNavigation {
    public static func codexURL(provider: String, sourceID: String?) -> URL? {
        guard provider == "Codex", let sourceID, let id = UUID(uuidString: sourceID) else { return nil }
        return URL(string: "codex://threads/" + id.uuidString.lowercased())
    }
}
