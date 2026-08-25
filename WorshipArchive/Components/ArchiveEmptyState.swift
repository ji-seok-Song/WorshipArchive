import SwiftUI

struct ArchiveEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let actionSystemImage: String?
    let action: (() -> Void)?
    let isCompact: Bool

    init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        actionSystemImage: String? = nil,
        action: (() -> Void)? = nil,
        isCompact: Bool = false
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.action = action
        self.isCompact = isCompact
    }

    var body: some View {
        Group {
            if isCompact {
                compactContent
            } else {
                regularContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding(isCompact ? 14 : 24)
        .background(ArchiveTheme.surface, in: .rect(cornerRadius: 20))
    }

    private var regularContent: some View {
        VStack(spacing: 18) {
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
            .accessibilityElement(children: .combine)

            if let actionTitle, let action {
                Button(action: action) {
                    if let actionSystemImage {
                        Label(actionTitle, systemImage: actionSystemImage)
                    } else {
                        Text(actionTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("찬양 악보 PDF를 선택합니다")
            }
        }
    }

    private var compactContent: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(ArchiveTheme.tint)
                .frame(width: 44, height: 44)
                .background(ArchiveTheme.tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
