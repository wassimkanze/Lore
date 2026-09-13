import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \ActivityBlock.startedAt) private var allBlocks: [ActivityBlock]
    @Query private var allCommits: [GitCommit]
    @Query private var sessions: [AISession]
    @Environment(AppState.self) private var state
    @Binding var selectedDay: Date?
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let anchor = selectedDay ?? timeline.date
            let day = Calendar.current.dateInterval(of: .day, for: anchor)!
            let blocks = ActivitySummary.blocks(allBlocks, in: day)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        PageHeading(title: selectedDay == nil ? "Today" : anchor.formatted(.dateTime.weekday(.wide)),
                                    subtitle: anchor.formatted(date: .complete, time: .omitted))
                        Spacer()
                        if selectedDay != nil { Button("Back to today") { selectedDay = nil }.controlSize(.small) }
                    }
                    HStack(spacing: 24) {
                        MetricView(title: "Observed activity", value: LoreFormat.duration(ActivitySummary.duration(blocks, in: day)), icon: "clock")
                        MetricView(title: "AI sessions", value: ActivitySummary.sessions(blocks, in: day).count.formatted(), icon: "sparkle")
                        MetricView(title: "Indexed commits", value: allCommits.filter { $0.timestamp >= day.start && $0.timestamp < day.end }.count.formatted(), icon: "point.3.connected.trianglepath.dotted")
                        MetricView(title: "Projects", value: Set(blocks.compactMap { $0.project?.id }).count.formatted(), icon: "folder")
                    }
                    ActivityCalendar(blocks: allBlocks, now: timeline.date, selection: $selectedDay)
                    if state.folders.repositoryPolicy.roots.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.badge.plus").foregroundStyle(LorePalette.accent)
                            Text("Connect your project folders to refresh Git history.").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Connect folders…") { Task { if await state.folders.chooseFolder(initialPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Code").path) { await state.accessChanged() } } }
                                .controlSize(.small).disabled(state.isIndexing)
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 28) {
                            activity(blocks, day: day).frame(minWidth: 410, maxWidth: .infinity)
                            Divider()
                            UsageOverview(sessions: sessions).frame(width: 260)
                        }
                        VStack(alignment: .leading, spacing: 28) {
                            activity(blocks, day: day)
                            Divider()
                            UsageOverview(sessions: sessions)
                        }
                    }
                }.padding(32).frame(maxWidth: 1180).frame(maxWidth: .infinity)
            }.navigationTitle("Today")
        }
    }
    private func activity(_ blocks: [ActivityBlock], day: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("What you worked on").font(.title3.weight(.semibold))
                Spacer()
                Button("Timeline →") { state.destination = .timeline }.buttonStyle(.plain).font(.caption).foregroundStyle(LorePalette.accent)
            }
            if blocks.isEmpty {
                QuietEmptyState(title: state.isIndexing ? "Reading your local history" : "A fresh page", description: "Choose a day in the calendar to revisit your work.", symbol: "sun.max")
            } else {
                VStack(spacing: 0) { ForEach(blocks) { block in ActivityRow(block: block, day: day); Divider().opacity(0.6) } }
            }
            Text("Observed time excludes gaps between recorded tasks. A period can span longer; overlapping work is counted once.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
