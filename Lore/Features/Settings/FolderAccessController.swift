import SwiftUI
import AppKit
import Observation

@MainActor @Observable final class FolderAccessController {
    private(set) var grants: [FolderGrant] = []
    private(set) var unavailableIDs: Set<UUID> = []
    private(set) var enabledProviders: Set<String>
    var errorMessage: String?
    @ObservationIgnored private var scopedURLs: [UUID: URL] = [:]
    @ObservationIgnored private var acquiredScopes: Set<UUID> = []
    private static let grantsKey = "folderGrants.v1"
    private static let providersKey = "enabledProviders.v1"
    init() {
        enabledProviders = Set(UserDefaults.standard.stringArray(forKey: Self.providersKey) ?? ["Codex", "Claude Code", "Gemini CLI"])
        if let data = UserDefaults.standard.data(forKey: Self.grantsKey) {
            do { grants = try JSONDecoder().decode([FolderGrant].self, from: data) }
            catch { errorMessage = "Saved folder access could not be restored. Choose your development folders again." }
        }
        var refreshed = false
        for index in grants.indices {
            let grant = grants[index]
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: grant.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                let started = url.startAccessingSecurityScopedResource()
                if started { acquiredScopes.insert(grant.id) }
                scopedURLs[grant.id] = url
                if stale {
                    guard started else { unavailableIDs.insert(grant.id); scopedURLs.removeValue(forKey: grant.id); continue }
                    grants[index].bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                    grants[index].path = url.path; refreshed = true
                }
            } catch {
                if acquiredScopes.remove(grant.id) != nil { scopedURLs[grant.id]?.stopAccessingSecurityScopedResource() }
                scopedURLs.removeValue(forKey: grant.id); unavailableIDs.insert(grant.id)
            }
        }
        if refreshed { persist() }
    }
    var repositoryPolicy: RepositoryAccessPolicy {
        RepositoryAccessPolicy(roots: grants.filter { $0.purpose == "projects" && !unavailableIDs.contains($0.id) }.compactMap { scopedURLs[$0.id]?.path })
    }
    var integrations: [any AIProviderIntegration] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func directory(_ provider: String, fallback: String) -> URL? {
            guard enabledProviders.contains(provider) else { return nil }
            if let grant = grants.first(where: { $0.purpose == "source:" + provider }) { return scopedURLs[grant.id] }
            return home.appendingPathComponent(fallback)
        }
        var sources: [any AIProviderIntegration] = []
        if let url = directory("Codex", fallback: ".codex") { sources.append(CodexIntegration(directory: url)) }
        if let url = directory("Claude Code", fallback: ".claude") { sources.append(ClaudeCodeIntegration(directory: url)) }
        if let url = directory("Gemini CLI", fallback: ".gemini") { sources.append(GeminiCLIIntegration(directory: url)) }
        return sources
    }
    func setProvider(_ provider: String, enabled: Bool) {
        if enabled { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
        UserDefaults.standard.set(enabledProviders.sorted(), forKey: Self.providersKey)
    }
    func chooseFolder(purpose: String = "projects", initialPath: String? = nil) async -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false; panel.showsHiddenFiles = true
        panel.title = purpose == "projects" ? "Choose a development folder" : "Choose the agent data folder"
        panel.message = purpose == "projects" ? "Lore will read Git metadata inside this folder. Your project files remain unchanged." : "Lore reads session metadata only. Prompts and responses are not saved."
        panel.prompt = "Allow Read Access"
        if let initialPath { panel.directoryURL = URL(fileURLWithPath: initialPath) }
        guard await panel.begin() == .OK, let url = panel.url else { return false }
        do {
            let started = url.startAccessingSecurityScopedResource()
            let bookmark: Data
            do { bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) }
            catch { if started { url.stopAccessingSecurityScopedResource() }; throw error }
            let duplicates = grants.filter { $0.purpose == purpose && (purpose != "projects" || $0.path == url.path) }
            for grant in duplicates { remove(grant) }
            let grant = FolderGrant(purpose: purpose, path: url.path, bookmark: bookmark)
            grants.append(grant); scopedURLs[grant.id] = url
            if started { acquiredScopes.insert(grant.id) }
            persist(); errorMessage = nil
            return true
        } catch { errorMessage = "This folder could not be saved. Choose it again to renew access."; return false }
    }
    func remove(_ grant: FolderGrant) {
        if acquiredScopes.remove(grant.id) != nil { scopedURLs[grant.id]?.stopAccessingSecurityScopedResource() }
        scopedURLs.removeValue(forKey: grant.id); unavailableIDs.remove(grant.id)
        grants.removeAll { $0.id == grant.id }; persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(grants) { UserDefaults.standard.set(data, forKey: Self.grantsKey) }
    }
}
