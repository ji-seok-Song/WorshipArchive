import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]
    @Query(sort: \ArchiveDocument.importedAt, order: .reverse) private var documents: [ArchiveDocument]
    @State private var viewModel = LibraryViewModel()

    let fileAccess: any PDFFileStoring
    let addPDF: () -> Void

    init(
        fileAccess: any PDFFileStoring = LocalPDFFileStore.live(),
        addPDF: @escaping () -> Void = {}
    ) {
        self.fileAccess = fileAccess
        self.addPDF = addPDF
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let displayedSongs = viewModel.displayedSongs(from: songs)

        VStack(spacing: 16) {
            Picker("라이브러리 보기", selection: $viewModel.mode) {
                ForEach(LibraryMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.horizontal)

            if viewModel.mode == .songs, !songs.isEmpty {
                HStack(spacing: 12) {
                    keyMenu

                    Toggle(isOn: $viewModel.showsFavoritesOnly) {
                        Label("즐겨찾기만", systemImage: "heart.fill")
                    }
                    .toggleStyle(.button)
                    .tint(ArchiveTheme.accent)

                    Spacer()

                    Text("\(displayedSongs.count)곡")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if viewModel.hasActiveSongFilter {
                        Button("초기화", systemImage: "arrow.counterclockwise") {
                            viewModel.resetSongFilters()
                        }
                        .font(.subheadline)
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal)
            }

            ScrollView {
                libraryContent(displayedSongs: displayedSongs)
                    .frame(maxWidth: 760)
                    .padding(.horizontal)
                    .padding(.bottom, 96)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
        .background(ArchiveTheme.background)
        .navigationTitle("라이브러리")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addPDF) {
                    Label("PDF 추가", systemImage: "plus")
                }
            }
        }
        .alert(
            "즐겨찾기를 저장하지 못했어요",
            isPresented: Binding(
                get: { viewModel.favoriteSaveErrorMessage != nil },
                set: { if !$0 { viewModel.favoriteSaveErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.favoriteSaveErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .alert(
            "원본 PDF를 삭제하지 못했어요",
            isPresented: Binding(
                get: { viewModel.documentDeleteErrorMessage != nil },
                set: { if !$0 { viewModel.documentDeleteErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.documentDeleteErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .confirmationDialog(
            "원본 PDF와 연결된 악보를 삭제할까요?",
            isPresented: Binding(
                get: { viewModel.documentPendingDeletion != nil },
                set: { if !$0 { viewModel.documentPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.documentPendingDeletion
        ) { document in
            Button("삭제", role: .destructive) {
                Task {
                    await viewModel.delete(
                        document,
                        in: modelContext,
                        fileStore: fileAccess
                    )
                }
            }
            Button("취소", role: .cancel) {}
        } message: { document in
            Text("‘\(document.originalFileName)’과 이 PDF에만 연결된 곡이 함께 삭제됩니다.")
        }
    }

    @ViewBuilder
    private func libraryContent(displayedSongs: [Song]) -> some View {
        switch viewModel.mode {
        case .songs:
            if songs.isEmpty {
                emptyState
            } else if displayedSongs.isEmpty {
                filteredSongsEmptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(displayedSongs, id: \.id) { song in
                        SongLibraryRow(
                            title: song.title,
                            subtitle: viewModel.keySummary(for: song),
                            isFavorite: song.isFavorite,
                            toggleFavorite: {
                                viewModel.toggleFavorite(for: song, in: modelContext)
                            }
                        ) {
                            SongPDFDestinationView(
                                song: song,
                                fileAccess: fileAccess
                            )
                        }
                    }
                }
            }
        case .documents:
            if documents.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(documents, id: \.id) { document in
                        NavigationLink {
                            PDFViewerView(
                                document: document,
                                sheet: nil,
                                fileAccess: fileAccess
                            )
                        } label: {
                            LibraryItemRow(
                                title: document.originalFileName,
                                subtitle: "\(document.pageCount)페이지",
                                systemImage: "doc.richtext"
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("삭제", systemImage: "trash", role: .destructive) {
                                viewModel.documentPendingDeletion = document
                            }
                        }
                    }
                }
            }
        }
    }

    private var keyMenu: some View {
        Menu {
            @Bindable var viewModel = viewModel
            Picker("키", selection: $viewModel.selectedKey) {
                Text("모든 키")
                    .tag(nil as MusicalKey?)

                ForEach(MusicalKey.allCases) { key in
                    Text(key.displayName)
                        .tag(key as MusicalKey?)
                }
            }
        } label: {
            Label(
                viewModel.selectedKey?.displayName ?? "모든 키",
                systemImage: "music.quarternote.3"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("키 필터")
        .accessibilityValue(viewModel.selectedKey?.displayName ?? "모든 키")
    }

    private var filteredSongsEmptyState: some View {
        ArchiveEmptyState(
            systemImage: viewModel.showsFavoritesOnly ? "heart" : "music.note",
            title: "조건에 맞는 곡이 없어요",
            message: viewModel.filteredSongsEmptyMessage(),
            actionTitle: "필터 초기화",
            actionSystemImage: "arrow.counterclockwise",
            action: viewModel.resetSongFilters
        )
    }

    private var emptyState: some View {
        ArchiveEmptyState(
            systemImage: viewModel.mode.systemImage,
            title: viewModel.mode.emptyTitle,
            message: viewModel.mode.emptyMessage,
            actionTitle: "PDF 추가",
            actionSystemImage: "plus",
            action: addPDF
        )
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

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(ArchiveTheme.surface, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("원본 PDF를 엽니다")
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(AppModelContainer.preview)
}
