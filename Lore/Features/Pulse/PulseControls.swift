import SwiftUI

struct PulseControls: View {
    let pulse: PulseController
    var onSetup: () -> Void = {}
    var compact = false
    var body: some View {
        @Bindable var preferences = pulse.preferences
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            HStack(spacing: 10) {
                PulseIndicator(rhythm: pulse.rhythm, tint: pulse.isActive ? LorePalette.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pulse").font(compact ? .headline : .title2.weight(.semibold))
                    Text(pulse.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if pulse.canStop { Button("Stop") { Task { await pulse.stop() } }.disabled(pulse.busy).controlSize(.small) }
            }
            if !pulse.canStop {
                if !preferences.pulsePresets.isEmpty {
                    Menu("Presets") {
                        ForEach(preferences.pulsePresets) { preset in
                            Button(preset.name + " · " + preset.duration.title) { preferences.applyPreset(preset) }
                        }
                    }.menuStyle(.borderlessButton).fixedSize().disabled(pulse.busy)
                }
                Picker("Pulse mode", selection: $preferences.pulseMode) {
                    ForEach(PulseMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().disabled(pulse.busy)
                HStack {
                    Picker("Duration", selection: $preferences.pulseDuration) {
                        ForEach(PulseDuration.allCases.filter { preferences.pulseMode != .closedLid || $0 != .agents }) { Text($0.title).tag($0) }
                    }.labelsHidden().fixedSize().disabled(pulse.busy)
                    Spacer()
                    if pulse.needsSetup {
                        Button("Set up Pulse", action: onSetup).buttonStyle(.borderedProminent)
                    } else {
                        Button("Start Pulse") { Task { await pulse.start() } }.buttonStyle(.borderedProminent).disabled(pulse.busy || pulse.closedLid.busy)
                    }
                }.controlSize(compact ? .small : .regular)
            }
            Text(pulse.isActive ? "Your Mac keeps working. The display can rest." : preferences.pulseMode == .closedLid ? "Keep working with the lid closed, on battery or charger." : "Prevent idle sleep while the lid stays open.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let message = pulse.message { Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
