import SwiftUI

/// Session-wide observations stay separate from the calendar's daily metrics.
struct UsageOverview: View {
    let sessions: [AISession]
    private var summary: UsageSummary {
        UsageSummary(sessions.map { SessionUsage(id: $0.id, model: $0.model, input: $0.inputTokens, output: $0.outputTokens, cached: $0.cachedTokens) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Your AI usage").font(.title3.weight(.semibold))
                Spacer()
                Text("All history").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(LoreFormat.tokens(summary.total)).font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
                Text("observed tokens").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                tokenLabel("Input", value: summary.input)
                tokenLabel("Output", value: summary.output)
                tokenLabel("Cached", value: summary.cached)
            }
            Divider()
            VStack(spacing: 12) {
                ForEach(["Codex", "Claude Code", "Gemini CLI"], id: \.self) { provider in
                    let count = sessions.filter { $0.provider == provider }.count
                    HStack {
                        Text(provider).font(.callout)
                        Spacer()
                        Text(count == 0 ? "No history" : "\(count) sessions").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text("Most-used models").font(.callout.weight(.medium))
            ForEach(Array(summary.models.prefix(5).enumerated()), id: \.element.id) { index, model in
                VStack(spacing: 7) {
                    HStack {
                        Text(model.name).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1).help(model.name)
                        Spacer(minLength: 8)
                        Text(model.sessions.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(.quaternary)
                        Capsule().fill(LorePalette.accent.opacity(max(0.35, 1 - Double(index) * 0.15)))
                            .frame(width: geometry.size.width * CGFloat(model.sessions) / CGFloat(max(1, summary.sessions)))
                    }.frame(height: 3)
                }
            }
            Text("Session totals, not billing or daily usage. Cached tokens are included in input. Models ranked by sessions.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func tokenLabel(_ title: String, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(LoreFormat.tokens(value)).font(.callout.weight(.medium)).monospacedDigit().help(value?.formatted() ?? "Unavailable")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LorePanel: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.07)) }
    }
}
extension View {
    func lorePanel() -> some View { modifier(LorePanel()) }
}
