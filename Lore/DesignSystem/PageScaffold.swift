import SwiftUI

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 30, weight: .semibold)).tracking(-0.7)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct InlineNotice: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.badge.questionmark").font(.title3).foregroundStyle(LorePalette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action).buttonStyle(.bordered).controlSize(.small)
        }.padding(16).background(LorePalette.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct QuietEmptyState: View {
    let title: String
    let description: String
    let symbol: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(LorePalette.accent.opacity(0.8))
            Text(title).font(.title3.weight(.medium))
            Text(description).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }.frame(maxWidth: .infinity, minHeight: 190).padding(20)
    }
}
