// Explicit development fixture; no simulated sessions enter the running monitor.
import SwiftUI
import AppKit

@main struct RenderNotchPreview {
    @MainActor static func main() throws {
        let now = Date()
        let samples = [
            LiveSession(id: "fixture-one", provider: "Codex", projectName: "Lore", phase: .working, startedAt: now, updatedAt: now),
            LiveSession(id: "fixture-two", provider: "Codex", projectName: "Example API", phase: .needsInput, startedAt: now, updatedAt: now),
            LiveSession(id: "fixture-three", provider: "Claude Code", projectName: "Example app", phase: .working, startedAt: now, updatedAt: now)
        ]
                let artwork = VStack(spacing: 24) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    PulseTrace(rhythm: .awake, phase: 0.2).frame(width: 32, height: 20).frame(width: 44)
                    Color.clear.frame(width: 180)
                    AIStarGlyph(summary: LiveActivitySummary(samples), phase: 1).frame(width: 44, height: 32)
                }.frame(height: 38)
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Text("AI activity").font(.headline); Spacer(); Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                    ForEach(samples) { session in
                        HStack(spacing: 10) {
                            Circle().fill(session.phase == .needsInput ? .orange : .white).frame(width: 6, height: 6)
                            Text(session.projectName! + " · " + session.provider).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(session.phase.label).font(.caption).foregroundStyle(session.phase == .needsInput ? Color.orange : Color.white.opacity(0.65))
                        }
                    }
                }.padding(22).foregroundStyle(.white)
            }.frame(width: 430).background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
            Text("Lore · aperçu de développement · regroupement par IA")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(.horizontal, 24).padding(.bottom, 20).frame(width: 540).background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let bitmap = NSBitmapImageRep(cgImage: image)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
