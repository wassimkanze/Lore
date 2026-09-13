// Development rendering only. The third rhythm does not enable closed-lid mode.
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct RenderPulsePreview {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let frameCount = 48
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<frameCount {
            let elapsed = Double(frame) / 20
            let artwork = VStack(alignment: .leading, spacing: 18) {
                Text("Lore · aperçu des pulsations").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                VStack(spacing: 12) {
                    row("Normal", rhythm: .resting, time: elapsed)
                    row("Maintien éveillé", rhythm: .awake, time: elapsed)
                    row("Clapet fermé · futur mode", rhythm: .closedLidConfirmed, time: elapsed)
                }
                Text("Aperçu de développement — le troisième mode n’est pas encore activable.")
                    .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.5))
            }.padding(24).frame(width: 440, alignment: .leading).background(.black)
            let renderer = ImageRenderer(content: artwork)
            renderer.scale = 2
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            if frame == 8 {
                let bitmap = NSBitmapImageRep(cgImage: image)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.deletingPathExtension().appendingPathExtension("png"))
            }
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05, kCGImagePropertyGIFUnclampedDelayTime: 0.05]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
    @MainActor static func row(_ title: String, rhythm: PulseRhythm, time: TimeInterval) -> some View {
        HStack(spacing: 20) {
            PulseTrace(rhythm: rhythm, phase: time * rhythm.cyclesPerSecond).frame(width: 32, height: 20).frame(width: 44, height: 28)
            Text(title).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.82))
            Spacer()
        }
    }
}
