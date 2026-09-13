import SwiftUI


enum Destination: String, CaseIterable, Identifiable {
    case today = "Today", timeline = "Timeline", projects = "Projects", pulse = "Pulse"
    case appearance = "Appearance", sources = "Sources & Access", privacy = "Privacy", diagnostics = "Diagnostics"
    var id: String { rawValue }
    var glyph: LoreGlyph.Kind { switch self { case .today: .today; case .timeline: .timeline; case .projects: .projects; case .pulse: .pulse; case .appearance: .appearance; case .sources: .sources; case .privacy: .privacy; case .diagnostics: .diagnostics } }
}
struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var selectedDay: Date?
    @State private var settingsExpanded = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || LorePreferences.shared.reduceMotion }
    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Destination?>(get: { state.destination }, set: { if let value = $0 { state.destination = value } })) {
                Section("Activity") {
                    ForEach([Destination.today, .timeline, .projects]) { item in
                        Label { Text(item.rawValue) } icon: { LoreGlyph(kind: item.glyph) }.padding(.vertical, 5).tag(item)
                    }
                }
                Section("Keep working") {
                    HStack {
                        Label { Text("Pulse") } icon: { LoreGlyph(kind: .pulse) }
                        Spacer()
                        if state.pulse.isActive { Circle().fill(LorePalette.accent).frame(width: 6, height: 6).accessibilityLabel("Active") }
                    }.padding(.vertical, 5).tag(Destination.pulse)
                }
                Section {
                    DisclosureGroup("Settings", isExpanded: $settingsExpanded) {
                        ForEach([Destination.appearance, .sources, .privacy]) { item in
                            Label { Text(item.rawValue).font(.callout) } icon: { LoreGlyph(kind: item.glyph) }.padding(.vertical, 4).tag(item)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 185, ideal: 215, max: 260)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 9) {
                    LoreMark().frame(width: 24, height: 24)
                    Text("Lore").font(.system(size: 24, weight: .semibold)).tracking(-0.8)
                    Spacer()
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("On this Mac", systemImage: "lock.shield").font(.caption.weight(.medium))
                    Text(state.lastIndexedAt.map { "Updated " + $0.formatted(date: .omitted, time: .shortened) } ?? "Ready to read local activity")
                        .font(.caption2).foregroundStyle(.tertiary)
                }.foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            Group {
                switch state.destination {
                case .today: TodayView(selectedDay: $selectedDay)
                case .timeline: TimelineView()
                case .projects: ProjectsView()
                case .pulse: PulseView()
                case .appearance: SettingsView(page: .appearance)
                case .sources: SettingsView(page: .sources)
                case .privacy: SettingsView(page: .privacy)
                case .diagnostics: SettingsView(page: .diagnostics)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: state.destination)
            .toolbar {
                ToolbarItem {
                    Button { Task { await state.refresh() } } label: { Label("Refresh Activity", systemImage: "arrow.clockwise") }
                        .disabled(state.isIndexing).help("Refresh local activity (⌘R)")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if state.isIndexing {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(state.progress?.message ?? "Refreshing activity").font(.caption)
                        if let progress = state.progress, progress.total > 0 {
                            Text("\(progress.completed) / \(progress.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Cancel") { state.cancelRefresh() }.controlSize(.small)
                    }.padding(.horizontal, 20).padding(.vertical, 11).background(.bar)
                } else if let error = state.errorMessage {
                    HStack {
                        Label(error, systemImage: "exclamationmark.circle").font(.caption)
                        Spacer(); Button("Dismiss") { state.errorMessage = nil }.controlSize(.small)
                    }.padding(12).background(.bar)
                }
            }
        }
        .tint(LorePalette.accent).preferredColorScheme(state.preferences.theme.scheme).frame(minWidth: 960, minHeight: 640)
        .onAppear {
            state.notch.openPulsePage = { [weak state] in
                state?.destination = .pulse; openWindow(id: "main"); NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}
