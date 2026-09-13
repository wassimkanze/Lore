import SwiftUI

/// Public project links only. Opening a link is always an explicit user action.
enum LoreSupport {
    static let repositoryURL = URL(string: "https://github.com/wassimkanze/Lore")!
    // Set once the maintainer supplies a verified public donation page.
    static let donationURL: URL? = nil
}

struct SupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 18) {
                    LoreMark().frame(width: 44, height: 44)
                    PageHeading(title: "Support Lore", subtitle: "Help a small, independent app keep growing.")
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("Free to use. Supported by you.").font(.title2.weight(.semibold))
                    Text("Lore is free. If it makes your day a little easier, an optional donation helps support development and maintenance.")
                        .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let url = LoreSupport.donationURL {
                        Link(destination: url) { Label("Support with a donation", systemImage: "heart") }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        Text("Opens the donation page in your browser. Lore does not collect payment details.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("The donation page is not available yet. You can already help by sharing Lore or contributing feedback.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Donations never unlock features. Everyone gets the same app.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LorePalette.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 16) {
                    Text("There are other ways to help").font(.headline)
                    Label("Share Lore with someone who might find it useful.", systemImage: "arrow.up.right")
                    Label("Tell us what works, what breaks, and what is missing.", systemImage: "bubble.left")
                    Label("Help improve the code, documentation or design.", systemImage: "chevron.left.forwardslash.chevron.right")
                    Link("View the project on GitHub ↗", destination: LoreSupport.repositoryURL)
                        .foregroundStyle(LorePalette.accent)
                }.font(.callout)
            }.padding(32).frame(maxWidth: 880).frame(maxWidth: .infinity)
        }.navigationTitle("Support Lore")
    }
}
