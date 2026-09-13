// Render the shared vector identity into the macOS icon sizes. No image service or dependency.
import SwiftUI
import AppKit

@MainActor struct AppIconArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 220, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.27, green: 0.20, blue: 0.50), Color(red: 0.12, green: 0.08, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 220, style: .continuous).strokeBorder(.white.opacity(0.13), lineWidth: 3)
            LoreSpark()
                .fill(LinearGradient(colors: [Color(red: 0.96, green: 0.91, blue: 1), Color(red: 0.69, green: 0.62, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 650, height: 650).shadow(color: .black.opacity(0.20), radius: 32, y: 18)
        }.padding(36).frame(width: 1024, height: 1024)
    }
}

@main struct RenderIcon {
    @MainActor static func main() throws {
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let renderer = ImageRenderer(content: AppIconArtwork().scaleEffect(CGFloat(pixels) / 1024, anchor: .topLeading).frame(width: CGFloat(pixels), height: CGFloat(pixels), alignment: .topLeading))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { fatalError("Icon rendering failed") }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let filename = "icon_\(size)x\(size)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))

    }
}
