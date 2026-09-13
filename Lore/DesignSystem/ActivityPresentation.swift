import SwiftUI

enum LoreFormat {
    static func tokens(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if seconds > 0 && minutes == 0 { return "<1m" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

struct ActivityRow: View {
    let block: ActivityBlock
    var day: DateInterval? = nil
    @State private var showingDetail = false
    @State private var hovering = false
    private var start: Date { max(block.startedAt, day?.start ?? block.startedAt) }
    private var end: Date { min(block.endedAt, day?.end ?? block.endedAt) }
    private var visibleSessions: [AISession] { day.map { ActivitySummary.sessions([block], in: $0) } ?? block.sessions }
    private var visibleCommits: [GitCommit] { day.map { range in block.commits.filter { $0.timestamp >= range.start && $0.timestamp < range.end } } ?? block.commits }
    var body: some View {
        Button { showingDetail = true } label: {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(start, style: .time).font(.callout.monospacedDigit())
                    Text(end, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }.frame(width: 72, alignment: .leading)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(block.project?.name ?? "Unassigned project").font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(LoreFormat.duration(end.timeIntervalSince(start))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(Array(Set(visibleSessions.map(\.provider))).sorted().joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) { counts; changes }
                        VStack(alignment: .leading, spacing: 6) { counts; changes }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(hovering ? LorePalette.accent : Color.secondary.opacity(0.5)).padding(.top, 4)
            }.padding(.vertical, LorePreferences.shared.compact ? 10 : 16).padding(.horizontal, 10)
                .background(hovering ? LorePalette.accent.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .sheet(isPresented: $showingDetail) { SessionDetailView(block: block, day: day) }
    }
    private var counts: some View {
        HStack(spacing: 12) {
            Label("\(visibleSessions.count) \(visibleSessions.count == 1 ? "session" : "sessions")", systemImage: "sparkle")
            Label("\(visibleCommits.count) \(visibleCommits.count == 1 ? "commit" : "commits")", systemImage: "point.3.connected.trianglepath.dotted")
        }.fixedSize()
    }
    @ViewBuilder private var changes: some View {
        if !visibleCommits.isEmpty {
            HStack(spacing: 8) {
                Text("+\(visibleCommits.reduce(0) { $0 + $1.additions })").foregroundStyle(.green)
                Text("−\(visibleCommits.reduce(0) { $0 + $1.deletions })").foregroundStyle(.red)
            }.monospacedDigit().fixedSize()
        }
    }
}

struct MetricView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || LorePreferences.shared.reduceMotion }
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText()).animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ActivitySummary {
    static func blocks(_ blocks: [ActivityBlock], in day: DateInterval) -> [ActivityBlock] {
        blocks.filter { ActivityInterval(start: $0.startedAt, end: $0.endedAt).overlaps(day) }
    }
    static func duration(_ blocks: [ActivityBlock], in day: DateInterval) -> TimeInterval {
        ActivityGroupingService.duration(of: sessions(blocks, in: day).flatMap(\.activityIntervals), within: day)
    }
    static func sessions(_ blocks: [ActivityBlock], in day: DateInterval) -> [AISession] {
        var found: [String: AISession] = [:]
        for session in blocks.flatMap(\.sessions) where session.activityIntervals.contains(where: { $0.overlaps(day) }) { found[session.id] = session }
        return found.values.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }
}
