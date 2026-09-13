import SwiftUI
import SwiftData

struct HistoryDay: Identifiable { var date: Date; var blocks: [ActivityBlock]; var id: Date { date } }
struct TimelineView: View {
    @Query(sort: \ActivityBlock.startedAt, order: .reverse) private var blocks: [ActivityBlock]
    @Query(sort: \Project.name) private var projects: [Project]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || LorePreferences.shared.reduceMotion }
    @State private var search = ""
    @State private var provider = "All agents"
    @State private var projectID = "All projects"
    @State private var calendarOpen = false
    @State private var selectedDay: Date?
    private var filtered: [ActivityBlock] {
        blocks.filter { block in
            let matchesProvider = provider == "All agents" || block.sessions.contains { $0.provider == provider }
            let matchesProject = projectID == "All projects" || block.project?.id == projectID
            let searchable = [block.project?.name ?? "", block.project?.path ?? ""] + block.sessions.compactMap(\.model) + block.commits.map(\.message)
            let matchesSearch = search.isEmpty || searchable.contains { $0.localizedCaseInsensitiveContains(search) }
            let matchesDay = selectedDay.map { date in
                let day = Calendar.current.dateInterval(of: .day, for: date)!
                return ActivityInterval(start: block.startedAt, end: block.endedAt).overlaps(day)
            } ?? true
            return matchesProvider && matchesProject && matchesSearch && matchesDay
        }
    }
    private var days: [HistoryDay] {
        var groups: [Date: [ActivityBlock]] = [:]
        for block in filtered {
            var day = Calendar.current.startOfDay(for: block.startedAt)
            repeat {
                if selectedDay == nil || Calendar.current.isDate(day, inSameDayAs: selectedDay!) { groups[day, default: []].append(block) }
                guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { break }; day = next
            } while day < block.endedAt
        }
        return groups.keys.sorted(by: >).map { HistoryDay(date: $0, blocks: groups[$0]!.sorted { $0.startedAt < $1.startedAt }) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Timeline", subtitle: "Follow the work across projects and agents.")
                HStack(spacing: 12) {
                    Picker("Agent", selection: $provider) {
                        Text("All agents").tag("All agents")
                        ForEach(["Codex", "Claude Code", "Gemini CLI"], id: \.self) { Text($0).tag($0) }
                    }.frame(maxWidth: 220)
                    Picker("Project", selection: $projectID) {
                        Text("All projects").tag("All projects")
                        ForEach(projects) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 250)
                    Spacer()
                    Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { calendarOpen.toggle() } } label: { Label("Calendar", systemImage: "calendar") }
                }
                if calendarOpen { ActivityCalendar(blocks: blocks, now: .now, selection: $selectedDay) }
                if let selectedDay {
                    HStack { Text(selectedDay.formatted(date: .complete, time: .omitted)).font(.callout); Button("Clear date") { self.selectedDay = nil }.controlSize(.small) }
                }
                HStack { Text("\(filtered.count) activity periods").font(.caption).foregroundStyle(.secondary); Spacer()
                    if !search.isEmpty || provider != "All agents" || projectID != "All projects" || selectedDay != nil {
                        Button("Reset filters") { search = ""; provider = "All agents"; projectID = "All projects"; selectedDay = nil }.controlSize(.small)
                    }
                }
                if filtered.isEmpty { QuietEmptyState(title: "No matching activity", description: "Try another project, agent or date. Search covers project names, models and commit messages.", symbol: "line.3.horizontal.decrease.circle") }
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(day.date.formatted(date: .complete, time: .omitted)).font(.headline)
                            Spacer()
                            Text(LoreFormat.duration(ActivitySummary.duration(day.blocks, in: Calendar.current.dateInterval(of: .day, for: day.date)!))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.padding(.bottom, 8)
                        ForEach(day.blocks) { block in ActivityRow(block: block, day: Calendar.current.dateInterval(of: .day, for: day.date)); Divider().opacity(0.6) }
                    }
                }
            }.padding(32)
        }.navigationTitle("Timeline").searchable(text: $search, prompt: "Projects, models or commits")
    }
}
