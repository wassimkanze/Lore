import AppKit
import Foundation
import Observation

public struct AppVersion: Comparable, Equatable, Sendable {
    public let components: [Int]
    public init?(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
            .split(separator: "-", maxSplits: 1)[0]
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ Int($0).map { $0 >= 0 } == true }) else { return nil }
        components = parts.map { Int($0)! }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

@MainActor @Observable final class AppUpdateController {
    enum Result: Equatable {
        case idle, checking, current, available(version: String, url: URL), failed
    }
    private(set) var result: Result = .idle
    private(set) var lastCheckedAt: Date?
    private let endpoint = URL(string: "https://api.github.com/repos/wassimkanze/Lore/releases/latest")!
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
    var isChecking: Bool { result == .checking }
    var availableURL: URL? {
        if case .available(_, let url) = result { return url }
        return nil
    }
    var statusLabel: String {
        switch result {
        case .idle: "Not checked"
        case .checking: "Checking GitHub…"
        case .current: "Lore is up to date"
        case .available(let version, _): "Lore \(version) is available"
        case .failed: "Couldn’t check for updates"
        }
    }

    func check() async {
        guard !isChecking else { return }
        result = .checking
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Lore/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateError.invalidResponse }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard release.pageURL.scheme == "https", release.pageURL.host == "github.com",
                  release.pageURL.path.hasPrefix("/wassimkanze/Lore/releases/") else { throw UpdateError.invalidResponse }
            guard let latest = AppVersion(release.tagName), let current = AppVersion(currentVersion) else { throw UpdateError.invalidVersion }
            result = current < latest ? .available(version: String(release.tagName.trimmingPrefix("v")), url: release.pageURL) : .current
            lastCheckedAt = .now
        } catch {
            result = .failed
            lastCheckedAt = .now
        }
    }

    func openAvailableRelease() {
        guard let availableURL else { return }
        NSWorkspace.shared.open(availableURL)
    }

    private struct Release: Decodable {
        let tagName: String
        let pageURL: URL
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", pageURL = "html_url" }
    }
    private enum UpdateError: Error { case invalidResponse, invalidVersion }
}
