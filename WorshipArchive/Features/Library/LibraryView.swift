import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Song.title) private var songs: [Song]
    @Query(sort: \ArchiveDocument.importedAt, order: .reverse) private var documents: [ArchiveDocument]
    @State private var mode: LibraryMode = .songs

    var body: some View {
        VStack(spacing: 16) {
            Picker("라이브러리 보기", selection: $mode) {
                ForEach(LibraryMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.horizontal)

            ScrollView {
                libraryContent
                    .frame(maxWidth: 620)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 8)
        .background(ArchiveTheme.background)
        .navigationTitle("라이브러리")
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch mode {
        case .songs:
            if songs.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(songs, id: \.id) { song in
                        LibraryItemRow(
                            title: song.title,
                            subtitle: keySummary(for: song),
                            systemImage: "music.note"
                        )
                    }
                }
            }
        case .documents:
            if documents.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(documents, id: \.id) { document in
                        LibraryItemRow(
                            title: document.originalFileName,
                            subtitle: "\(document.pageCount)페이지",
                            systemImage: "doc.richtext"
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ArchiveEmptyState(
            systemImage: mode.systemImage,
            title: mode.emptyTitle,
            message: mode.emptyMessage
        )
    }

    private func keySummary(for song: Song) -> String {
        let keyNames = Set(
            song.sheets?.compactMap { $0.musicalKey?.displayName } ?? []
        ).sorted()

        switch keyNames.count {
        case 0:
            return "키 미지정"
        case 1...2:
            return keyNames.joined(separator: " · ")
        default:
            return "\(keyNames[0]) 외 \(keyNames.count - 1)개 키"
        }
    }
}

private struct LibraryItemRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ArchiveTheme.tint)
                .frame(width: 44, height: 44)
                .background(ArchiveTheme.tint.opacity(0.12), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(ArchiveTheme.surface, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private enum LibraryMode: String, CaseIterable, Identifiable {
    case songs
    case documents

    var id: Self { self }

    var title: String {
        switch self {
        case .songs: "곡별"
        case .documents: "PDF별"
        }
    }

    var systemImage: String {
        switch self {
        case .songs: "music.note.list"
        case .documents: "doc.richtext"
        }
    }

    var emptyTitle: String {
        switch self {
        case .songs: "등록된 곡이 없어요"
        case .documents: "보관 중인 PDF가 없어요"
        }
    }

    var emptyMessage: String {
        switch self {
        case .songs: "PDF 분석을 확인하면 곡별 악보가 여기에 모여요."
        case .documents: "가져온 원본 PDF를 변경 없이 안전하게 보관해요."
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(AppModelContainer.preview)
}
