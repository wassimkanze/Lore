import SwiftUI
import SwiftData
import OSLog

@main struct LoreApp: App {
    private let container: ModelContainer?
    private let isTestHost: Bool
    @State private var state: AppState?
    init() {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
        isTestHost = testing
        if testing { Logger(subsystem: "app.lore.mac", category: "App").info("Test host: temporary storage; live indexing disabled") }
        do {
            let database = try LoreDatabase.make(inMemory: testing)
            container = database
            _state = State(initialValue: AppState(container: database))
        } catch {
            container = nil
            _state = State(initialValue: nil)
        }
    }
    var body: some Scene {
        Window("Lore", id: "main") {
            if let container, let state {
                ContentView().environment(state).modelContainer(container)
                    .task { if !isTestHost { await state.start() } }
            } else {
                ContentUnavailableView("Lore couldn’t open its database", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text("Your saved data has not been removed. Check available disk space and access to Application Support/Lore, then reopen Lore."))
                    .frame(width: 620, height: 380)
            }
        }
        .defaultSize(width: 1200, height: 840)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Support Lore…") { state?.openSupportPage?() }
                    .disabled(state == nil)
            }
            CommandMenu("Pulse") {
                Button("Toggle Pulse") { Task { await state?.pulse.toggle() } }
                    .keyboardShortcut("p", modifiers: [.command, .option]).disabled(state?.pulse.busy != false)
                Button("Stop Pulse") { Task { await state?.pulse.stop() } }
                    .keyboardShortcut(".", modifiers: [.command, .option]).disabled(state?.pulse.canStop != true || state?.pulse.busy != false)
                Divider()
                Button("Show Pulse") { state?.notch.openPulsePage?() }
                    .keyboardShortcut("p", modifiers: [.command, .shift]).disabled(state == nil)
            }
            CommandGroup(after: .newItem) {
                Button("Show AI Task Details") { state?.notch.showDetails(NotchController.agentsID) }
                    .keyboardShortcut("a", modifiers: [.command, .shift]).disabled(state?.notch.isEnabled != true)
                Button("Refresh Activity") { Task { await state?.refresh() } }
                    .keyboardShortcut("r", modifiers: .command).disabled(state?.isIndexing != false)
            }
        }
        Settings {
            if let container, let state { SettingsView().environment(state).modelContainer(container).frame(width: 820, height: 640) }
        }
        MenuBarExtra {
            if let container, let state { LoreMenuView().environment(state).modelContainer(container) }
            else { Button("Quit Lore") { NSApplication.shared.terminate(nil) } }
        } label: {
            Image(nsImage: LoreMenuIcon.image).accessibilityLabel("Lore")
            if let state, state.preferences.showPulseTime, state.pulse.isActive { Text(state.pulse.remaining).monospacedDigit() }
        }.menuBarExtraStyle(.window)
    }
}
