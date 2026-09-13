import SwiftUI
import SwiftData

struct LoreMenuView: View {
    @Query(sort: \ActivityBlock.startedAt, order: .reverse) private var blocks: [ActivityBlock]
    @Query private var projects: [Project]
    @Environment(\.openWindow) private var openWindow
    @Environment(AppState.self) private var state
    var body: some View {
        let day = Calendar.current.dateInterval(of: .day, for: .now)!
        let today = ActivitySummary.blocks(blocks, in: day)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                LoreMark().frame(width: 23, height: 23)
                Text("Lore").font(.title3.weight(.semibold))
                Spacer()
                Button { open(.today) } label: { Image(systemName: "arrow.up.right") }.buttonStyle(.plain).help("Open Lore")
            }
            HStack(spacing: 24) {
                metric(LoreFormat.duration(ActivitySummary.duration(today, in: day)), label: "Today")
                metric(ActivitySummary.sessions(today, in: day).count.formatted(), label: "AI sessions")
                Spacer()
            }
            Divider()
            PulseControls(pulse: state.pulse, onSetup: { open(.pulse) }, compact: true)
            Divider()
            if !state.notch.experience.rows.isEmpty {
                HStack { Text("Live & recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Button("All tasks") { state.notch.showDetails(NotchController.agentsID) }.buttonStyle(.plain).font(.caption).disabled(!state.notch.isEnabled) }
                ForEach(Array(state.notch.experience.rows.prefix(3))) { session in
                    Button { AgentApplicationIcons.openSession(provider: session.provider, sourceID: session.sourceID) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(session.phase == .needsInput ? .orange : session.phase == .completed ? .green : LorePalette.accent).frame(width: 5, height: 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.projectName ?? session.provider).font(.callout.weight(.medium)).lineLimit(1)
                                Text(session.provider + " · " + session.statusLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Divider()
            }
            HStack {
                Button { Task { await state.refresh() } } label: { Label(state.isIndexing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise") }.disabled(state.isIndexing)
                Spacer()
                Menu {
                    let favorites = state.preferences.favoriteProjectIDs.compactMap { id in projects.first { $0.id == id } }
                    if favorites.isEmpty { Button("Choose favorites in Projects…") { open(.projects) } }
                    ForEach(favorites) { project in
                        Button(project.name) { state.selectedProjectID = project.id; open(.projects) }
                    }
                } label: { Label("Favorites", systemImage: "star") }.menuStyle(.borderlessButton).fixedSize()
                Menu {
                    Section("Explore") {
                        Button("Timeline") { open(.timeline) }
                        Button("Projects") { open(.projects) }
                        Button("Pulse") { open(.pulse) }
                    }
                    Section("Settings") {
                        Button("Appearance…") { open(.appearance) }
                        Button("Sources & Access…") { open(.sources) }
                        Button("Diagnostics…") { open(.diagnostics) }
                    }
                    Divider()
                    Button("Support Lore…") { open(.support) }
                    Button("Quit Lore") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("More Lore actions")
            }.controlSize(.small)
        }.padding(20).frame(width: 360).tint(LorePalette.accent)
            .preferredColorScheme(state.preferences.theme.scheme)
            .task { await state.closedLid.refresh() }
    }
    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }
    }
    private func open(_ destination: Destination) {
        state.destination = destination; openWindow(id: "main"); NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
