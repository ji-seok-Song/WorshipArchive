import SwiftUI

struct SongLibraryRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    private let destination: () -> Destination

    init(
        title: String,
        subtitle: String,
        isFavorite: Bool,
        toggleFavorite: @escaping () -> Void,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isFavorite = isFavorite
        self.toggleFavorite = toggleFavorite
        self.destination = destination
    }

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                destination()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "music.note")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ArchiveTheme.tint)
                        .frame(width: 44, height: 44)
                        .background(
                            ArchiveTheme.tint.opacity(0.12),
                            in: .rect(cornerRadius: 12)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .padding(.leading, 14)
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(title)
                .accessibilityValue(subtitle)
                .accessibilityHint("곡의 악보 PDF를 엽니다")
            }
            .buttonStyle(.plain)

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(isFavorite ? ArchiveTheme.accent : .secondary)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .accessibilityLabel(isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가")
            .accessibilityHint("이 곡의 즐겨찾기 상태를 변경합니다")
        }
        .background(ArchiveTheme.surface, in: .rect(cornerRadius: 16))
    }
}
