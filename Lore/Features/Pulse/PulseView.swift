import SwiftUI

struct PulseView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 22) {
                    PulseIndicator(rhythm: state.pulse.rhythm, tint: LorePalette.accent).scaleEffect(1.8).frame(width: 68, height: 60)
                    PageHeading(title: "Pulse", subtitle: "Keep your Mac in the flow.")
                }
                HStack(alignment: .top, spacing: 36) {
                    PulseControls(pulse: state.pulse, onSetup: {
                        if state.closedLid.requiresApproval { state.closedLid.openApprovalSettings() }
                        else { Task { await state.closedLid.configure() } }
                    })
                        .padding(24).frame(maxWidth: .infinity)
                        .background(LorePalette.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 24) {
                        mode("Stay awake", detail: "Your Mac stays available while the lid is open. The display can rest.", icon: "sun.max")
                        mode("Lid closed", detail: "Your agents keep working with the lid closed, on battery or charger.", icon: "laptopcomputer")
                    }.frame(width: 240).padding(.top, 10)
                }
                Divider()
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Built-in care", systemImage: "checkmark.shield").font(.headline)
                        Text("Lid-closed sessions stop at 20% battery, excessive heat or loss of contact with Lore. Use a ventilated surface; let the Mac sleep when carried in a bag.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("One gesture away", systemImage: "hand.point.up.left").font(.headline)
                        Text("Click the heartbeat to start or stop Pulse. In Lore: ⌥⌘P toggles Pulse, ⌥⌘. stops it, and ⇧⌘P opens this page.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Personalize Pulse →") { state.destination = .appearance }.buttonStyle(.plain).foregroundStyle(LorePalette.accent)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                PulsePresetsView(pulse: state.pulse)
                access
            }.padding(32).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.navigationTitle("Pulse").task { await state.closedLid.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await state.closedLid.refresh() } }
    }
    private func mode(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.callout.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var access: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("System access").font(.headline)
                Spacer()
                Label(state.closedLid.registration, systemImage: state.closedLid.isRegistered ? "checkmark.circle" : "lock").font(.caption).foregroundStyle(.secondary)
            }
            if !state.closedLid.isRegistered {
                Text("Enable system access once to use Pulse with the lid closed. macOS handles approval.").font(.callout).foregroundStyle(.secondary)
                if state.closedLid.requiresApproval {
                    Button("Approve in System Settings") { state.closedLid.openApprovalSettings() }
                } else {
                    Button("Enable Pulse system access") { Task { await state.closedLid.configure() } }.disabled(!state.closedLid.canConfigure || state.closedLid.busy)
                }
            }
            if let message = state.closedLid.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Check connection") { Task { await state.closedLid.refresh() } }
                Button("Diagnostics…") { state.destination = .diagnostics }
                Spacer()
                if state.closedLid.isRegistered {
                    Menu {
                        Button("Remove system access") { Task { await state.closedLid.removeAuthorization() } }
                            .disabled(state.closedLid.leaseInUse || state.closedLid.restorationPending || state.closedLid.busy)
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("System access options")
                }
            }.controlSize(.small)
        }.padding(20).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
}
