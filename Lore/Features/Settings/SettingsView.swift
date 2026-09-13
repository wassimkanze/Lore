import SwiftUI
import SwiftData

enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance = "Appearance", sources = "Sources & Access", privacy = "Privacy", diagnostics = "Diagnostics"
    var id: String { rawValue }
    var glyph: LoreGlyph.Kind { switch self { case .appearance: .appearance; case .sources: .sources; case .privacy: .privacy; case .diagnostics: .diagnostics } }
    var subtitle: String { switch self { case .appearance: "Make Lore feel like yours."; case .sources: "Choose what Lore can read."; case .privacy: "Your development data stays on this Mac."; case .diagnostics: "Local indexing and system checks." } }
}
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Query private var sessions: [AISession]
    var page: SettingsPage? = nil
    var body: some View {
        Group {
            if let page {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        LoreGlyph(kind: page.glyph).foregroundStyle(LorePalette.accent)
                        PageHeading(title: page.rawValue, subtitle: page.subtitle)
                    }.padding(.horizontal, 32).padding(.top, 28)
                    Form {
                        switch page {
                        case .appearance: appearance
                        case .sources: sources
                        case .privacy: privacy
                        case .diagnostics: general; validation
                        }
                    }.formStyle(.grouped)
                }.navigationTitle(page.rawValue)
            } else {
                TabView {
                    ForEach(SettingsPage.allCases) { page in
                        SettingsView(page: page).tabItem { Label { Text(page.rawValue) } icon: { LoreGlyph(kind: page.glyph) } }
                    }
                }.padding(12)
            }
        }.preferredColorScheme(state.preferences.theme.scheme).tint(LorePalette.accent)
            .task { await state.closedLid.refresh() }
    }
    @ViewBuilder private var appearance: some View {
        @Bindable var preferences = state.preferences
        Section("Look & feel") {
            Picker("Appearance", selection: $preferences.theme) { ForEach(LoreTheme.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            HStack(spacing: 16) {
                Text("Accent"); Spacer()
                ForEach(LoreAccent.allCases) { accent in
                    Button { preferences.accent = accent } label: {
                        Circle().fill(accent.color).frame(width: 24, height: 24)
                            .overlay { if preferences.accent == accent { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
                    }.buttonStyle(.plain).help(accent.rawValue).accessibilityLabel(accent.rawValue)
                        .accessibilityAddTraits(preferences.accent == accent ? .isSelected : [])
                }
            }
            Toggle("Compact activity rows", isOn: $preferences.compact)
            Toggle("Reduce animations", isOn: $preferences.reduceMotion)
            Text("Lore also follows macOS Reduce Motion. The notch keeps its opaque black surface.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Live island") {
            Toggle("Show the notch", isOn: Binding(get: { state.notch.isEnabled }, set: { state.notch.setEnabled($0) }))
            Toggle("Brief attention and completion updates", isOn: Binding(get: { state.notch.announcementsEnabled }, set: { state.notch.setAnnouncementsEnabled($0) }))
            Toggle("More relaxed hover timing", isOn: $preferences.relaxedHover)
            Text("Hover for a glance, click for details. Pin only when you want it to stay open. Hiding the notch does not stop Pulse.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Pulse defaults") {
            Picker("Mode", selection: $preferences.pulseMode) { ForEach(PulseMode.allCases) { Text($0.rawValue).tag($0) } }
            Picker("Duration", selection: $preferences.pulseDuration) { ForEach(PulseDuration.allCases.filter { preferences.pulseMode != .closedLid || $0 != .agents }) { Text($0.title).tag($0) } }
            Toggle("Show remaining Pulse time in the menu bar", isOn: $preferences.showPulseTime)
            Text("Defaults apply the next time you start Pulse. Changing them does not activate it.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Preview") {
            HStack(spacing: 18) {
                LoreMark().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) { Text("Lore").font(.headline); Text("Remember what you built.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                PulseIndicator(rhythm: .awake, tint: LorePalette.accent)
                Text("Pulse").font(.callout)
            }.padding(.vertical, 8)
        }
    }
    @ViewBuilder private var validation: some View {
        Section("Validate on this Mac") {
            Text("A three-minute check, on battery or charger: close the lid for 30–60 seconds, then reopen it. Lore measures sampling continuity and restores normal sleep afterwards.")
                .font(.caption).foregroundStyle(.secondary)
            if state.lidValidation.running {
                Button("Stop test and restore sleep") { Task { await state.lidValidation.finish() } }
            } else {
                Button("Start closed-lid check…") { Task { await state.lidValidation.start(power: state.closedLid) } }
                    .disabled(!state.closedLid.canStart)
            }
            if let message = state.lidValidation.message { Text(message).font(.callout).foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private var general: some View {
        Section("Local index") {
            LabeledContent("Sessions indexed", value: sessions.count.formatted())
            LabeledContent("Database", value: "Stored on this Mac")
            LabeledContent("Last refresh", value: state.lastIndexedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not refreshed yet")
            if let report = state.report {
                LabeledContent("Source files", value: report.discoveredFiles.formatted())
                LabeledContent("Files parsed this refresh", value: report.parsedFiles.formatted())
                Text("Unchanged session metadata is reused across launches.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Skipped files / Git errors", value: "\(report.skippedFiles) / \(report.gitFailures)")
            }
            Button(state.isIndexing ? "Refreshing…" : "Refresh local activity") { Task { await state.refresh() } }.disabled(state.isIndexing)
        }
        Section("Time estimates") {
            Text("Periods group nearby work with a 30-minute threshold. Observed time excludes gaps between recorded Codex tasks and counts concurrent work once. Older logs use timestamp estimates; this is not keyboard or CPU tracking.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var sources: some View {
        Section("AI sources") {
            ForEach(ProviderIntegrations.defaults(), id: \.provider) { source in
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(source.provider, isOn: Binding(get: { state.folders.enabledProviders.contains(source.provider) }, set: { value in
                        state.folders.setProvider(source.provider, enabled: value)
                        Task { await state.accessChanged() }
                    })).font(.callout.weight(.medium))
                    let selected = state.folders.grants.first { $0.purpose == "source:" + source.provider }
                    let report = state.report?.providers.first { $0.provider == source.provider }
                    HStack {
                        Text((selected?.path ?? source.directory.path) as String).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(sessions.filter { $0.provider == source.provider }.count) sessions").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        let needsRenewal = selected.map { state.folders.unavailableIDs.contains($0.id) } ?? false
                        Label(needsRenewal ? "Access needs renewal" : !state.folders.enabledProviders.contains(source.provider) ? "Paused" : (report?.detected ?? source.isDetected) ? "Data folder detected" : "No local history found",
                              systemImage: needsRenewal ? "exclamationmark.circle" : "externaldrive")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(needsRenewal ? "Renew access…" : "Choose folder…") {
                            Task { if await state.folders.chooseFolder(purpose: "source:" + source.provider, initialPath: selected?.path ?? source.directory.path) { await state.accessChanged() } }
                        }.controlSize(.small)
                    }
                    if let note = report?.note ?? source.diagnosticNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 6)
            }
        }.disabled(state.isIndexing)
        Section("Development folders") {
            Text("Lore reads Git history only inside folders you choose. Grant a parent folder such as Code to include its projects. Removing access keeps your indexed history.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(state.folders.grants.filter { $0.purpose == "projects" }) { grant in
                HStack {
                    Image(systemName: state.folders.unavailableIDs.contains(grant.id) ? "folder.badge.questionmark" : "checkmark.shield").foregroundStyle(LorePalette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text((grant.path as NSString).abbreviatingWithTildeInPath).font(.callout).lineLimit(1).truncationMode(.middle)
                        Text(state.folders.unavailableIDs.contains(grant.id) ? "Choose the folder again to renew access" : "Read-only access saved").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { state.folders.remove(grant); Task { await state.accessChanged() } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help("Remove this folder's access")
                }
            }
            Button("Add development folder…") { Task { if await state.folders.chooseFolder(initialPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Code").path) { await state.accessChanged() } } }
            if let error = state.folders.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }.disabled(state.isIndexing)
        Section("Permissions between updates") {
            Label(SignedIdentity.teamID == nil ? "Temporary development signature" : "Stable developer signature", systemImage: "checkmark.seal").font(.callout.weight(.medium))
            Text("Folder choices are saved as read-only bookmarks. Keep using the installed copy of Lore and updates signed by the same developer. Moving from an older temporary build may require one final authorization from macOS.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var privacy: some View {
        Section {
            Label("Your development data stays on this Mac.", systemImage: "lock.shield").font(.headline)
            Text("No account, backend, analytics, telemetry or cloud sync. Lore reads your local history and stores activity metadata in its own database.").foregroundStyle(.secondary)
        }
        Section("What Lore saves") {
            Label("Project paths and activity timestamps", systemImage: "folder")
            Label("Agent names, models and available token counters", systemImage: "sparkle")
            Label("Git authors, commit messages and change statistics", systemImage: "point.3.connected.trianglepath.dotted")
        }
        Section("What stays out") {
            Text("Prompts, responses, source code, credentials and API keys are not stored. Lore does not modify your projects, Git settings or agent logs.").foregroundStyle(.secondary)
        }
        Section("Storage") {
            Text("~/Library/Application Support/Lore/Lore.store").font(.caption.monospaced()).textSelection(.enabled)
            Text("Revoking folder access stops future Git reads; it does not erase already indexed metadata.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
