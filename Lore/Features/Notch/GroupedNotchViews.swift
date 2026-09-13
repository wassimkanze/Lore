import SwiftUI

struct PulseBadgeView: View {
    let controller: NotchController
    var body: some View {
        Button { controller.toggleKeepAwake() } label: {
            PulseIndicator(rhythm: controller.closedLid.isActive ? .closedLidConfirmed : controller.keepAwake.isActive ? .awake : .resting)
                .frame(width: 44, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel((controller.keepAwake.isActive || controller.closedLid.isActive) ? "Stop keeping Mac awake" : "Keep Mac awake")
            .help(controller.powerStatus + " · hover for options")
    }
}

struct AIActivityBadgeView: View {
    let controller: NotchController
    var body: some View {
        Button { controller.showDetails(NotchController.agentsID) } label: {
            AIStarIndicator(summary: controller.activitySummary)
                .frame(width: 44, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("AI activity · \(controller.activitySummary.activeCount) active tasks · \(controller.activitySummary.label)")
            .help("Hover for a quick glance · click for all tasks and recent results")
    }
}

struct NotchPeekView: View {
    let title: String
    let subtitle: String
    let symbol: String
    var tint: Color = .white
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.62)).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
    }
}

struct ExpandedNotchView: View {
    let controller: NotchController
    let width: CGFloat
    let height: CGFloat
    let collapsedWidth: CGFloat
    let cameraWidth: CGFloat
    let topHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || LorePreferences.shared.reduceMotion }
    var body: some View {
        ZStack(alignment: .top) {
            GrowingNotchSurface(surfaceWidth: controller.isExpanded ? width : collapsedWidth,
                                surfaceHeight: controller.isExpanded ? height : topHeight)
                .fill(NotchSurface.black)
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: controller.isExpanded)
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: height)
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: width)
                .frame(width: width, height: height)
            VStack(spacing: 0) {
                // Fixed header geometry keeps both symbols anchored while the surface grows.
                HStack(spacing: 0) {
                    PulseBadgeView(controller: controller)
                    Color.clear.frame(width: cameraWidth)
                    AIActivityBadgeView(controller: controller)
                }.frame(height: topHeight)
                Group {
                    if controller.showsDetails {
                        if controller.selectedID == NotchController.powerID {
                            detailsContents.padding(18)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    controller.fitPowerPanel(to: height)
                                }
                        } else { detailsContents.padding(18) }
                    }
                    else {
                        Button { controller.showDetails(controller.selectedID ?? NotchController.agentsID) } label: {
                            peekContents.padding(18).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Show details")
                    }
                }
                    .opacity(controller.contentVisible && controller.isExpanded ? 1 : 0)
                    .offset(y: controller.contentVisible ? 0 : -5)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: controller.contentVisible)
            }
        }.frame(width: width, height: height, alignment: .top).clipped()
            .preferredColorScheme(.dark)
    }
    @ViewBuilder private var peekContents: some View {
        if controller.selectedID == NotchController.powerID {
            NotchPeekView(title: controller.powerStatus,
                          subtitle: controller.pulse?.isActive == true ? "Click to manage Pulse." : "Pulse · keep your Mac working.",
                          symbol: "waveform.path", tint: controller.keepAwake.isActive ? .white : .gray)
        } else if let notice = controller.announcement {
            NotchPeekView(title: notice.title, subtitle: notice.subtitle + " · " + (notice.count > 1 ? "view Details" : notice.session.provider),
                          symbol: notice.kind == .attention ? "exclamationmark.circle" : "checkmark",
                          tint: notice.kind == .attention ? .orange : .green)
        } else if let attention = controller.attentionSession {
            NotchPeekView(title: "\(controller.activitySummary.activeCount) active tasks · \(controller.experience.attention.count) need you",
                          subtitle: (attention.projectName ?? attention.provider) + " · " + attention.statusLabel,
                          symbol: "exclamationmark.circle", tint: .orange)
        } else {
            let summary = controller.activitySummary
            let quiet = summary.phase == .uncertain
            let stopped = summary.phase == .stopped
            let finished = summary.phase == .completed
            let title = quiet ? "Waiting for a fresh signal" : stopped ? "A task stopped" : finished ? "All observed tasks finished" : summary.activeCount > 0 ? "\(summary.activeCount) active \(summary.activeCount == 1 ? "task" : "tasks")" : "No active tasks"
            NotchPeekView(title: title,
                          subtitle: quiet || stopped ? "Open Details to check the latest state." : summary.activeCount > 0 ? "Your agents are working. Click for details." : controller.experience.recent.isEmpty ? "Your agents will appear here when they start." : "Recent results are available in Details.",
                          symbol: quiet ? "minus.circle" : stopped ? "xmark.circle" : finished ? "checkmark" : "sparkle",
                          tint: stopped ? .red : finished ? .green : .white)
        }
    }

    private var detailsContents: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(controller.selectedID == NotchController.powerID ? "Pulse" : "AI activity")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { controller.pin(controller.selectedID ?? NotchController.agentsID) } label: {
                    Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                }.buttonStyle(.plain).help(controller.isPinned ? "Unpin panel" : "Keep panel open")
                Button { controller.dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close panel")
            }.foregroundStyle(.white)
            if controller.selectedID == NotchController.powerID { powerContents }
            else {
                Text("Live tasks & recent results · 20 min").font(.caption2).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 0) {
                        if controller.groups.isEmpty {
                            Text("Nothing running right now").font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                        }
                        ForEach(controller.groups) { group in
                            HStack(spacing: 8) {
                                if let icon = AgentApplicationIcons.image(for: group.provider) {
                                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 15, height: 15)
                                }
                                Text(group.provider).font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Text("\(group.sessions.count) sessions").font(.caption2)
                            }.foregroundStyle(.white.opacity(0.65)).frame(height: 28)
                            ForEach(group.sessions) { session in sessionRow(session) }
                        }
                    }
                }.scrollIndicators(.hidden)
                if controller.pendingRowCount > 0 {
                    Button("\(controller.pendingRowCount) new tasks · update list") { controller.updateDisplayedRows() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.white).frame(height: 20)
                }
            }
        }
    }
    @ViewBuilder private var powerContents: some View {
        if let pulse = controller.pulse {
            PulseControls(pulse: pulse, onSetup: { controller.openPulsePage?(); controller.dismiss() }, compact: true)
        } else { Text(controller.powerStatus).font(.caption) }
    }
    private func sessionRow(_ session: LiveSession) -> some View {
        Button { AgentApplicationIcons.openSession(provider: session.provider, sourceID: session.sourceID) } label: {
            HStack(spacing: 12) {
                Circle().fill(session.phase == .needsInput ? .orange : session.phase == .completed ? .green : session.phase == .stopped ? .red : .white.opacity(0.6))
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.projectName ?? "Unassigned project").font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text(session.statusLabel).font(.system(size: 11)).foregroundStyle(session.phase == .needsInput ? .orange : .secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                let terminal = session.phase == .completed || session.phase == .stopped
                let time = terminal ? controller.experience.now.timeIntervalSince(session.updatedAt) : controller.experience.now.timeIntervalSince(session.startedAt)
                Text(session.phase == .uncertain ? "—" : LoreFormat.duration(max(0, time)) + (terminal ? " ago" : ""))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(height: 56).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help("\(SessionNavigation.codexURL(provider: session.provider, sourceID: session.sourceID) == nil ? "Open app" : "Open this chat") · \(session.provider) · \(session.model ?? "Model unavailable") · \(session.id.prefix(6))")
            .accessibilityLabel("\(session.projectName ?? session.provider), \(session.statusLabel), open \(session.provider)")
    }
}
