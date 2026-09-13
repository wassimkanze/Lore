import SwiftUI

struct PulsePresetsView: View {
    let pulse: PulseController
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your presets").font(.headline)
            Text("Load a saved mode and duration, then press Start Pulse. Saving or selecting a preset never starts a session.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(pulse.preferences.pulsePresets) { preset in
                HStack {
                    Button { pulse.preferences.applyPreset(preset) } label: {
                        HStack(spacing: 12) {
                            LoreGlyph(kind: .pulse).foregroundStyle(LorePalette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name).font(.callout.weight(.medium))
                                Text(preset.mode.rawValue + " · " + preset.duration.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(pulse.isActive || pulse.busy)
                    Spacer()
                    Menu { Button("Remove preset", role: .destructive) { pulse.preferences.removePreset(preset.id) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }.padding(.vertical, 5)
            }
            HStack {
                TextField("Name for the current setup", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Button("Save setup") {
                    if pulse.preferences.savePreset(name: name) { name = ""; error = nil }
                    else { error = "Use a name between 1 and 40 characters." }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pulse.isActive || pulse.busy)
                Spacer()
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
