import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    @State private var viewModel = SearchViewModel()

    let fileAccess: any StoredPDFAccessing
    let addPDF: () -> Void

    init(
        fileAccess: any StoredPDFAccessing = LocalPDFFileStore.live(),
        addPDF: @escaping () -> Void = {}
    ) {
        self.fileAccess = fileAccess
        self.addPDF = addPDF
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let displayedSongs = viewModel.displayedSongs(from: songs)
        let showsResults = viewModel.shouldShowResults
        let request = viewModel.searchRequest(for: songs)

        ScrollView {
            VStack(spacing: 16) {
                if songs.isEmpty {
                    ArchiveEmptyState(
                        systemImage: "doc.badge.plus",
                        title: "먼저 악보를 추가해 주세요",
                        message: "PDF를 등록하면 곡 제목과 원본 PDF 이름으로 찾을 수 있어요.",
                        actionTitle: "첫 PDF 추가",
                        actionSystemImage: "plus",
                        action: addPDF
                    )
                } else {
                    searchControls(
                        resultCount: displayedSongs.count,
                        showsResults: showsResults
                    )

                    if viewModel.isQueryPending {
                        ProgressView("검색 중…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if showsResults, !displayedSongs.isEmpty {
                        LazyVStack(spacing: 12) {
                            ForEach(displayedSongs, id: \.id) { song in
                                SongLibraryRow(
                                    title: song.title,
                                    subtitle: viewModel.searchResultSummary(for: song),
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
                    } else {
                        searchEmptyState(hasQuery: showsResults)
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding()
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchiveTheme.background)
        .navigationTitle("검색")
        .searchable(text: $viewModel.query, prompt: "곡 제목 또는 PDF 이름 검색")
        .task(id: request) {
            await viewModel.refreshSearch(for: request, songs: songs)
        }
        .onAppear {
            viewModel.refreshContent()
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
    }

    private func searchControls(
        resultCount: Int,
        showsResults: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(
                viewModel.isQueryPending
                    ? "검색 중…"
                    : showsResults ? "\(resultCount)곡" : "전체 \(songs.count)곡"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()

            if showsResults {
                Button("초기화", systemImage: "arrow.counterclockwise") {
                    viewModel.resetSearch()
                }
                .font(.subheadline)
            }
        }
        .padding(14)
        .background(ArchiveTheme.surface, in: .rect(cornerRadius: 16))
    }

    private func searchEmptyState(hasQuery: Bool) -> some View {
        ArchiveEmptyState(
            systemImage: hasQuery ? "music.note" : "text.magnifyingglass",
            title: hasQuery ? "검색 결과가 없어요" : "기억나는 단서를 입력해 보세요",
            message: hasQuery
                ? viewModel.emptyResultMessage()
                : "곡 제목이나 원본 PDF 이름을 검색해 보세요."
        )
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .modelContainer(AppModelContainer.preview)
}
