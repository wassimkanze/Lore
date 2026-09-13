// Explicit development fixtures; no simulated agents are inserted into Lore's index.
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct RenderAIStarPreview {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, 36, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let working = LiveActivitySummary([sample("a", .working), sample("b", .working), sample("c", .working)])
        let attention = LiveActivitySummary([sample("a", .needsInput)])
        let done = LiveActivitySummary([sample("a", .completed), sample("b", .completed)])
        for frame in 0..<36 {
            let phase = Double(frame) / 36 * .pi * 2
            let artwork = VStack(alignment: .leading, spacing: 18) {
                Text("Lore · une étoile pour toutes les IA").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                row("Au repos", summary: LiveActivitySummary([]), phase: 0)
                row("Trois tâches au travail", summary: working, phase: phase)
                row("Intervention nécessaire", summary: attention, phase: 0)
                row("Toutes les tâches terminées", summary: done, phase: 0)
                Text("Aperçu de développement").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.5))
            }.padding(24).frame(width: 440, alignment: .leading).background(.black)
            let renderer = ImageRenderer(content: artwork)
            renderer.scale = 2
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            if frame == 8 {
                try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                    .write(to: output.deletingPathExtension().appendingPathExtension("png"))
            }
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
    static func sample(_ id: String, _ phase: LivePhase) -> LiveSession {
        LiveSession(id: id, provider: "Preview", phase: phase, startedAt: .now, updatedAt: .now)
    }
    @MainActor static func row(_ title: String, summary: LiveActivitySummary, phase: Double) -> some View {
        HStack(spacing: 20) {
            AIStarGlyph(summary: summary, phase: phase).frame(width: 44, height: 32)
            Text(title).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.82))
            Spacer()
        }
    }
}
