import SwiftUI
import AppKit

@MainActor enum AgentApplicationIcons {
    private static var icons: [String: NSImage] = [:]
    static func applicationURL(for provider: String) -> URL? {
        let identifier: String
        switch provider {
        case "Codex": identifier = "com.openai.codex"
        case "Claude Code": identifier = "com.anthropic.claudefordesktop"
        case "Gemini CLI": identifier = "com.google.GeminiMacOS"
        default: return nil
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }
    static func image(for provider: String) -> NSImage? {
        if let image = icons[provider] { return image }
        guard let url = applicationURL(for: provider) else { return nil }
        let bundledCodex = provider == "Codex" ? Bundle(url: url)?.url(forResource: "icon-codex-dark-color", withExtension: "png").flatMap { NSImage(contentsOf: $0) } : nil
        let image = bundledCodex ?? NSWorkspace.shared.icon(forFile: url.path)
        icons[provider] = image
        return image
    }
    static func openSession(provider: String, sourceID: String?) {
        if let link = SessionNavigation.codexURL(provider: provider, sourceID: sourceID),
           let app = applicationURL(for: provider) {
            NSWorkspace.shared.open([link], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else { open(provider) }
    }
    static func open(_ provider: String) {
        guard let url = applicationURL(for: provider) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

