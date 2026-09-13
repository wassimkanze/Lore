import SwiftUI
import SwiftData
import AppKit

struct ProjectsView: View {
    @Query(sort: \Project.lastSeenAt, order: .reverse) private var projects: [Project]
    @Environment(AppState.self) private var state
    @State private var search = ""
    @State private var selection: String?
    @State private var allSessions = false
    @State private var allCommits = false
    private var filtered: [Project] {
        projects.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) }
            .sorted { a, b in
                let first = state.preferences.favoriteProjectIDs.firstIndex(of: a.id) ?? Int.max
                let second = state.preferences.favoriteProjectIDs.firstIndex(of: b.id) ?? Int.max
                return first == second ? a.lastSeenAt > b.lastSeenAt : first < second
            }
    }
    private var selected: Project? { projects.first { $0.id == selection } }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Projects").font(.title2.weight(.semibold)).padding(.horizontal, 16).padding(.top, 24)
                List(filtered, selection: $selection) { project in
                    HStack(spacing: 11) {
                        Image(systemName: "folder").foregroundStyle(LorePalette.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(project.name).font(.callout.weight(.medium))
                            Text(project.lastSeenAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if state.preferences.favoriteProjectIDs.contains(project.id) { Image(systemName: "star.fill").font(.caption2).foregroundStyle(LorePalette.accent).accessibilityLabel("Favorite") }
                        if !state.folders.repositoryPolicy.permits(project.path) { Image(systemName: "lock").font(.caption2).foregroundStyle(.tertiary) }
                    }.padding(.vertical, 8).tag(project.id)
                }.listStyle(.inset)
            }.frame(minWidth: 210, idealWidth: 240, maxWidth: 310)
            Group {
                if let selected { detail(selected) }
                else { QuietEmptyState(title: "Your projects, remembered", description: "Choose a project to explore its sessions, activity and Git history.", symbol: "folder") }
            }.frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        }.navigationTitle("Projects").searchable(text: $search, prompt: "Find a project")
            .onChange(of: selection) { _, _ in allSessions = false; allCommits = false }
            .onAppear { selection = state.selectedProjectID ?? selection ?? filtered.first?.id }
            .onChange(of: state.selectedProjectID) { _, id in if let id { search = ""; selection = id } }
            .onChange(of: search) { _, _ in if !filtered.contains(where: { $0.id == selection }) { selection = filtered.first?.id } }
    }
    private func detail(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: project.name, subtitle: (project.path as NSString).abbreviatingWithTildeInPath)
                HStack {
                    Label("First seen " + project.firstSeenAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { state.preferences.toggleFavorite(project.id) } label: {
                        Label(state.preferences.favoriteProjectIDs.contains(project.id) ? "Favorited" : "Favorite", systemImage: state.preferences.favoriteProjectIDs.contains(project.id) ? "star.fill" : "star")
                    }.controlSize(.small)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)]) } label: { Label("Finder", systemImage: "arrow.up.right") }
                        .controlSize(.small).disabled(!state.folders.repositoryPolicy.permits(project.path))
                }
                if !state.folders.repositoryPolicy.permits(project.path) {
                    InlineNotice(title: "Git access not connected", detail: "Allow read access to this project or its parent development folder.", actionTitle: "Allow access") {
                        Task { if await state.folders.chooseFolder(initialPath: project.path) { await state.accessChanged() } }
                    }.disabled(state.isIndexing)
                }
                HStack(spacing: 20) {
                    MetricView(title: "AI sessions", value: project.sessions.count.formatted(), icon: "sparkle")
                    MetricView(title: "Indexed commits", value: project.commits.isEmpty && !state.folders.repositoryPolicy.permits(project.path) ? "—" : project.commits.count.formatted(), icon: "point.3.connected.trianglepath.dotted")
                    MetricView(title: "Activity periods", value: project.blocks.count.formatted(), icon: "clock")
                }
                if let remote = project.gitRemote { Text(remote).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("Recent activity").font(.title3.weight(.semibold))
                ForEach(project.blocks.sorted { $0.startedAt > $1.startedAt }.prefix(6)) { block in
                    ActivityRow(block: block); Divider()
                }
                Text("AI sessions").font(.title3.weight(.semibold))
                    ForEach(project.sessions.sorted { $0.startedAt > $1.startedAt }.prefix(allSessions ? project.sessions.count : 5)) { session in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.provider).font(.callout.weight(.medium))
                                Button(SessionNavigation.codexURL(provider: session.provider, sourceID: session.sourceID) == nil ? "Open app ↗" : "Open chat ↗") {
                                    AgentApplicationIcons.openSession(provider: session.provider, sourceID: session.sourceID)
                                }.buttonStyle(.plain).font(.caption).foregroundStyle(LorePalette.accent)
                                Text(session.model ?? "Model unavailable").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 10); Divider()
                    }
                if project.sessions.count > 5 { Button(allSessions ? "Show fewer sessions" : "Show all \(project.sessions.count) sessions") { allSessions.toggle() }.buttonStyle(.plain).foregroundStyle(LorePalette.accent).font(.caption) }
                Text("Recent commits").font(.title3.weight(.semibold))
                    if project.commits.isEmpty { QuietEmptyState(title: "No indexed commits", description: "Git history appears after folder access is granted and activity is refreshed.", symbol: "point.3.connected.trianglepath.dotted") }
                    ForEach(project.commits.sorted { $0.timestamp > $1.timestamp }.prefix(allCommits ? project.commits.count : 5)) { commit in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(commit.message).font(.callout).textSelection(.enabled)
                            Text("\(commit.hash.prefix(8)) · \(commit.author) · \(commit.timestamp.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            Text("\(commit.filesChanged) files · +\(commit.additions) / −\(commit.deletions)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.padding(.vertical, 10); Divider()
                    }
                if project.commits.count > 5 { Button(allCommits ? "Show fewer commits" : "Show all \(project.commits.count) commits") { allCommits.toggle() }.buttonStyle(.plain).foregroundStyle(LorePalette.accent).font(.caption) }
            }.padding(28)
        }.id(project.id)
    }
}
