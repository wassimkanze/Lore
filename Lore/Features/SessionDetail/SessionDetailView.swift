import SwiftUI

struct SessionDetailView: View {
    let block: ActivityBlock
    var day: DateInterval?
    @Environment(AppState.self) private var state
    private var sessions: [AISession] { day.map { ActivitySummary.sessions([block], in: $0) } ?? block.sessions }
    private var commits: [GitCommit] { day.map { range in block.commits.filter { $0.timestamp >= range.start && $0.timestamp < range.end } } ?? block.commits }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.project?.name ?? "Activity").font(.title2.weight(.semibold))
                    Text(block.startedAt.formatted(date: .abbreviated, time: .shortened) + " – " + block.endedAt.formatted(date: .omitted, time: .shortened))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                let range = day ?? DateInterval(start: block.startedAt, end: block.endedAt)
                Text("Observed activity: " + LoreFormat.duration(ActivitySummary.duration([block], in: range))).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if let project = block.project {
                    Button("View project →") { state.selectedProjectID = project.id; state.destination = .projects; dismiss() }
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("AI sessions").font(.headline)
                    ForEach(sessions.sorted { $0.startedAt < $1.startedAt }) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.provider + " · " + (session.model ?? "Model unavailable")).font(.callout.weight(.medium))
                            Button(SessionNavigation.codexURL(provider: session.provider, sourceID: session.sourceID) == nil ? "Open app ↗" : "Open this chat in Codex ↗") {
                                AgentApplicationIcons.openSession(provider: session.provider, sourceID: session.sourceID)
                            }.buttonStyle(.plain).foregroundStyle(LorePalette.accent)
                            Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 16) {
                                Text("Input: \(session.inputTokens.map { $0.formatted() } ?? "—")")
                                Text("Output: \(session.outputTokens.map { $0.formatted() } ?? "—")")
                                Text("Cached: \(session.cachedTokens.map { $0.formatted() } ?? "—")")
                            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text("Session-wide token totals").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Divider()
                    Text("Nearby commits · \(commits.count)").font(.headline)
                    ForEach(commits.sorted { $0.timestamp < $1.timestamp }) { commit in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(commit.message).font(.callout).textSelection(.enabled)
                            Text("\(commit.hash.prefix(8)) · \(commit.author) · \(commit.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(commit.filesChanged) files · +\(commit.additions) / −\(commit.deletions)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    Text("Commits are associated by project and time proximity; this does not imply the AI authored them.")
                        .font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(26).frame(width: 660, height: 560)
    }
}
