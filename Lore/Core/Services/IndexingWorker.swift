import Foundation
import SwiftData
import OSLog

public struct ProviderIndexReport: Sendable, Identifiable {
    public var provider: String
    public var detected: Bool
    public var discoveredFiles: Int = 0
    public var indexedSessions: Int = 0
    public var skippedFiles: Int = 0
    public var discoveryFailed = false
    public var note: String?
    public var id: String { provider }
}

public struct IndexingProgress: Sendable {
    public var message: String
    public var completed: Int
    public var total: Int
}

public struct IndexingReport: Sendable {
    public var providers: [ProviderIndexReport]
    public var codexDetected: Bool { providers.first { $0.provider == "Codex" }?.detected ?? false }
    public var discoveredFiles: Int
    public var indexedSessions: Int
    public var projects: Int
    public var commits: Int
    public var blocks: Int
    public var skippedFiles: Int
    public var gitFailures: Int
    public var parsedFiles: Int
    public var projectsNeedingAccess: Int = 0
}

/// Owns scanning, Git enrichment and persistence off the main actor. SwiftUI never reads JSONL.
public actor IndexingWorker {
    private let container: ModelContainer
    private var integrations: [any AIProviderIntegration]
    private var repositoryAccess: RepositoryAccessPolicy = .unrestrictedAccess
    private let git = GitService()
    private let logger = Logger(subsystem: "app.lore.mac", category: "Indexing")
    private var cache = SessionIndexCache()
    private var cacheLoaded = false
    private let cacheURL: URL?
    public init(container: ModelContainer, integrations: [any AIProviderIntegration] = ProviderIntegrations.defaults(), cacheURL: URL? = nil) {
        self.container = container; self.integrations = integrations; self.cacheURL = cacheURL
    }
    /// A source-isolated convenience for tests and Codex-only diagnostics.
    public init(container: ModelContainer, codexDirectory: URL) {
        self.container = container; integrations = [CodexIntegration(directory: codexDirectory)]; cacheURL = nil
    }

    public func configure(integrations: [any AIProviderIntegration], repositoryAccess: RepositoryAccessPolicy) {
        self.integrations = integrations; self.repositoryAccess = repositoryAccess
    }
    public func index(progress: (@Sendable (IndexingProgress) -> Void)? = nil) throws -> IndexingReport {
        if !cacheLoaded { cache = SessionIndexCache.load(cacheURL); cacheLoaded = true }
        var seenKeys: Set<String> = []
        var parsed: [String: ParsedSession] = [:]
        var skipped = 0, readCount = 0, gitFailures = 0
        var reports: [ProviderIndexReport] = []
        for integration in integrations {
            var report = ProviderIndexReport(provider: integration.provider, detected: integration.isDetected, note: integration.diagnosticNote)
            let files: [URL]
            do { files = try integration.discoverSessions() }
            catch {
                report.discoveryFailed = true
                reports.append(report)
                logger.debug("One provider's session directory could not be enumerated")
                continue
            }
            report.discoveredFiles = files.count
            for (fileIndex, url) in files.enumerated() {
                try Task.checkCancellation()
                progress?(IndexingProgress(message: "Reading \(integration.provider)", completed: fileIndex, total: files.count))
                do {
                    let sources = [url] + integration.cacheDependencies(at: url)
                    let fingerprints = sources.map(SourceFingerprint.init)
                    let key = StableID.make(integration.provider, url.path)
                    seenKeys.insert(key)
                    let session: ParsedSession?
                    if let cached = cache.entries[key], cached.fingerprints == fingerprints {
                        session = cached.session
                    } else {
                        readCount += 1
                        session = try integration.parseSession(at: url)
                        // Files may still be written while we parse. Never cache that race.
                        if fingerprints == sources.map(SourceFingerprint.init) {
                            cache.entries[key] = SessionIndexCache.Entry(fingerprints: fingerprints, session: session)
                        } else { cache.entries.removeValue(forKey: key) }
                    }
                    guard let session else { skipped += 1; report.skippedFiles += 1; continue }
                    if let existing = parsed[session.id], (existing.endedAt ?? existing.startedAt) > (session.endedAt ?? session.startedAt) { continue }
                    parsed[session.id] = session
                } catch is CancellationError { throw CancellationError() }
                catch { skipped += 1; report.skippedFiles += 1; logger.debug("A session file could not be read") }
            }
            reports.append(report)
        }
        // A context confined to this actor; no persistent model crosses to the UI.
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            var projects = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Project>()).map { ($0.id, $0) })
            var sessions = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<AISession>()).map { ($0.id, $0) })
            var commits = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<GitCommit>()).map { ($0.id, $0) })
            progress?(IndexingProgress(message: "Matching projects", completed: 0, total: parsed.count))
            var blockedProjects: Set<String> = []
            var repositories: [String: RepositoryMetadata] = [:]
            var resolvedPaths: [String: String] = [:]
            for metadata in parsed.values.sorted(by: { $0.id < $1.id }) {
                let session = sessions[metadata.id] ?? AISession(metadata: metadata)
                if sessions[metadata.id] == nil { context.insert(session); sessions[metadata.id] = session }
                session.update(metadata)
                guard let cwd = metadata.workingDirectory else { continue }
                let lexical = URL(fileURLWithPath: cwd).standardizedFileURL.path
                let allowed = repositoryAccess.permits(lexical)
                let canonical = allowed ? URL(fileURLWithPath: lexical).resolvingSymlinksInPath().path : lexical
                let projectPath: String
                if let resolved = resolvedPaths[canonical] { projectPath = resolved }
                else {
                    if allowed && repositoryAccess.permits(canonical), let repository = try? git.repository(at: canonical) {
                        projectPath = repository.root; repositories[repository.root] = repository
                    } else {
                        projectPath = projects.values.filter { canonical == $0.path || canonical.hasPrefix($0.path + "/") }.max { $0.path.count < $1.path.count }?.path ?? canonical
                        if !allowed || !repositoryAccess.permits(canonical) { blockedProjects.insert(projectPath) }
                    }
                    resolvedPaths[canonical] = projectPath
                }
                let projectID = StableID.project(path: projectPath)
                let project = projects[projectID] ?? Project(path: projectPath, at: metadata.startedAt)
                if projects[projectID] == nil { context.insert(project); projects[projectID] = project }
                project.firstSeenAt = min(project.firstSeenAt, metadata.startedAt)
                project.lastSeenAt = max(project.lastSeenAt, metadata.endedAt ?? metadata.startedAt)
                if let repository = repositories[projectPath] { project.gitRemote = repository.remote }
                session.project = project
            }
            for (root, _) in repositories {
                try Task.checkCancellation()
                progress?(IndexingProgress(message: "Reading Git history", completed: 0, total: repositories.count))
                guard let project = projects[StableID.project(path: root)] else { continue }
                do {
                    let history = try git.commits(at: root, since: project.firstSeenAt.addingTimeInterval(-ActivityPolicy.inactivityThreshold),
                                                  until: project.lastSeenAt.addingTimeInterval(ActivityPolicy.inactivityThreshold))
                    for metadata in history {
                        let id = StableID.commit(projectID: project.id, hash: metadata.hash)
                        if commits[id] == nil {
                            let commit = GitCommit(metadata: metadata, project: project)
                            context.insert(commit); commits[id] = commit
                        }
                    }
                } catch { gitFailures += 1; logger.debug("Git enrichment unavailable for one project") }
            }
            let seeds = sessions.values.flatMap { session -> [ActivitySeed] in
                let projectID = session.project?.id ?? StableID.make("unassigned", session.id)
                return session.activityIntervals.map { ActivitySeed(sessionID: session.id, projectID: projectID, interval: $0) }
            }
            let groups = ActivityGroupingService().group(seeds)
            let existingBlocks = try context.fetch(FetchDescriptor<ActivityBlock>())
            let byID = Dictionary(uniqueKeysWithValues: existingBlocks.map { ($0.id, $0) })
            var updated: [ActivityBlock] = []
            for group in groups {
                let project = projects[group.projectID]
                let block = byID[group.id] ?? ActivityBlock(id: group.id, project: project, start: group.start, end: group.end)
                if byID[group.id] == nil { context.insert(block) }
                block.startedAt = group.start; block.endedAt = group.end
                block.sessions = group.sessionIDs.compactMap { sessions[$0] }; block.commits = []
                updated.append(block)
            }
            let validIDs = Set(groups.map(\.id))
            for block in existingBlocks where !validIDs.contains(block.id) { context.delete(block) }
            let blocksByProject = Dictionary(grouping: updated, by: { $0.project?.id ?? "" })
            for commit in commits.values {
                guard let project = commit.project else { continue }
                let nearby = (blocksByProject[project.id] ?? []).filter {
                    commit.timestamp >= $0.startedAt.addingTimeInterval(-ActivityPolicy.inactivityThreshold) &&
                    commit.timestamp <= $0.endedAt.addingTimeInterval(ActivityPolicy.inactivityThreshold)
                }
                // Exactly one association, even if two periods are equally close.
                if let block = nearby.min(by: {
                    let a = abs(commit.timestamp.timeIntervalSince($0.endedAt)), b = abs(commit.timestamp.timeIntervalSince($1.endedAt))
                    return a == b ? $0.id < $1.id : a < b
                }) { block.commits.append(commit) }
            }
            try Task.checkCancellation()
            progress?(IndexingProgress(message: "Saving activity", completed: 0, total: 1))
            try context.save()
            cache.entries = cache.entries.filter { seenKeys.contains($0.key) }
            do { try cache.save(cacheURL) }
            catch { logger.debug("Metadata cache unavailable; saved activity remains available") }
            logger.info("Indexed \(sessions.count) sessions, \(projects.count) projects, \(updated.count) activity blocks")
            for index in reports.indices {
                reports[index].indexedSessions = sessions.values.filter { $0.provider == reports[index].provider }.count
            }
            return IndexingReport(providers: reports, discoveredFiles: reports.reduce(0) { $0 + $1.discoveredFiles }, indexedSessions: sessions.count,
                                  projects: projects.count, commits: commits.count, blocks: updated.count,
                                  skippedFiles: skipped, gitFailures: gitFailures, parsedFiles: readCount, projectsNeedingAccess: blockedProjects.count)
        } catch { context.rollback(); throw error }
    }
}
