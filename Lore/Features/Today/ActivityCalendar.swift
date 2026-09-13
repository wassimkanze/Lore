import SwiftUI

/// Local-calendar days; color encodes observed duration, not tokens or productivity.
struct ActivityCalendar: View {
    let blocks: [ActivityBlock]
    let now: Date
    @Binding var selection: Date?
    private let columns = 26
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }
    private var days: [Date] {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let start = calendar.date(byAdding: .weekOfYear, value: -(columns - 1), to: week)!
        return (0..<(columns * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private func periods(on date: Date) -> [ActivityBlock] {
        ActivitySummary.blocks(blocks, in: calendar.dateInterval(of: .day, for: date)!)
    }
    private func duration(on date: Date) -> TimeInterval {
        ActivitySummary.duration(periods(on: date), in: calendar.dateInterval(of: .day, for: date)!)
    }
    private func color(on date: Date) -> Color {
        guard !periods(on: date).isEmpty else { return .primary.opacity(0.055) }
        let seconds = duration(on: date)
        return LorePalette.accent.opacity(seconds < 1800 ? 0.30 : seconds < 7200 ? 0.52 : seconds < 14400 ? 0.76 : 1)
    }
    var body: some View {
        let dates = days
        let activeDays = dates.filter { !periods(on: $0).isEmpty && $0 <= now }.count
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your activity").font(.title3.weight(.semibold))
                Spacer()
                Text("\(activeDays) active days").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text("· last 26 weeks").font(.caption).foregroundStyle(.tertiary)
            }
            GeometryReader { geometry in
                let side = min(22, max(10, (geometry.size.width - 21 - CGFloat(columns - 1) * 4) / CGFloat(columns)))
                HStack(alignment: .top, spacing: 9) {
                VStack(spacing: 4) {
                    Color.clear.frame(width: 12, height: 17)
                    ForEach(0..<7) { row in
                        Text(row == 0 ? "M" : row == 2 ? "W" : row == 4 ? "F" : "")
                            .font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 12, height: side)
                    }
                }
                HStack(alignment: .top, spacing: 4) {
                    ForEach(0..<columns, id: \.self) { column in
                        VStack(spacing: 4) {
                            let date = dates[column * 7]
                            let showMonth = column == 0 || calendar.component(.month, from: date) != calendar.component(.month, from: dates[(column - 1) * 7])
                            Text(showMonth ? date.formatted(.dateTime.month(.abbreviated)) : "")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                .fixedSize().frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                            ForEach(0..<7, id: \.self) { row in
                                cell(dates[column * 7 + row], width: side, height: side)
                            }
                        }.frame(width: side)
                    }
                }
                }
            }.frame(height: 200)
            HStack {
                Text("Select a day to revisit what you built.").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.3, 0.52, 0.76, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(level == 0 ? .primary.opacity(0.055) : LorePalette.accent.opacity(level)).frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(20).background(.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 16))
    }
    private func cell(_ date: Date, width: CGFloat, height: CGFloat) -> some View {
        let future = calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
        let selected = calendar.isDate(date, inSameDayAs: selection ?? now)
        let description = date.formatted(date: .complete, time: .omitted) + ", " + (periods(on: date).isEmpty ? "no indexed activity" : LoreFormat.duration(duration(on: date)) + " observed activity")
        return Button { selection = calendar.isDate(date, inSameDayAs: now) ? nil : date } label: {
            RoundedRectangle(cornerRadius: 3).fill(future ? .clear : color(on: date))
                .frame(width: width, height: height)
                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? LorePalette.accent : .clear, lineWidth: 1.5).padding(-2) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(future).help(description).accessibilityLabel(description)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
