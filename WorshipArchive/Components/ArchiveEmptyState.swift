import SwiftUI

struct ArchiveEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(ArchiveTheme.tint)
                .frame(width: 64, height: 64)
                .background(ArchiveTheme.tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(ArchiveTheme.surface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
