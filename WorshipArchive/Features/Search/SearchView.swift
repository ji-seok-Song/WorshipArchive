import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    @State private var query = ""
    @State private var favoriteSaveErrorMessage: String?
    @State private var committedQuery = ""
    @State private var matchingSongIDs: [UUID] = []
    @State private var searchRefreshID = UUID()

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
        let displayedSongs = displayedSongs
        let showsResults = shouldShowResults
        let request = searchRequest

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

                    if isQueryPending {
                        ProgressView("검색 중…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if showsResults, !displayedSongs.isEmpty {
                        LazyVStack(spacing: 12) {
                            ForEach(displayedSongs, id: \.id) { song in
                                SongLibraryRow(
                                    title: song.title,
                                    subtitle: searchResultSummary(for: song),
                                    isFavorite: song.isFavorite,
                                    toggleFavorite: {
                                        toggleFavorite(for: song)
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
        .searchable(text: $query, prompt: "곡 제목 또는 PDF 이름 검색")
        .task(id: request) {
            await refreshSearch(for: request)
        }
        .onAppear {
            searchRefreshID = UUID()
        }
        .alert(
            "즐겨찾기를 저장하지 못했어요",
            isPresented: favoriteErrorIsPresented
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(favoriteSaveErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private var filter: SongSearchFilter {
        SongSearchFilter(
            query: committedQuery
        )
    }

    private var displayedSongs: [Song] {
        let matchingIDs = Set(matchingSongIDs)
        return songs.filter { matchingIDs.contains($0.id) }
    }

    private var shouldShowResults: Bool {
        !SearchTextNormalizer.normalize(query).isEmpty
            || !filter.query.isEmpty
    }

    private var isQueryPending: Bool {
        SearchTextNormalizer.normalize(query)
            != SearchTextNormalizer.normalize(committedQuery)
    }

    private var searchRequest: SongSearchRefreshRequest {
        SongSearchRefreshRequest(
            query: query,
            contentRevisions: SongSearchContentRevision.capture(songs),
            refreshID: searchRefreshID
        )
    }

    private var favoriteErrorIsPresented: Binding<Bool> {
        Binding(
            get: { favoriteSaveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    favoriteSaveErrorMessage = nil
                }
            }
        )
    }

    private func searchControls(
        resultCount: Int,
        showsResults: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(
                isQueryPending
                    ? "검색 중…"
                    : showsResults ? "\(resultCount)곡" : "전체 \(songs.count)곡"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()

            if showsResults {
                Button("초기화", systemImage: "arrow.counterclockwise") {
                    resetSearch()
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
                ? emptyResultMessage
                : "곡 제목이나 원본 PDF 이름을 검색해 보세요."
        )
    }

    private var emptyResultMessage: String {
        let trimmedQuery = committedQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedQuery.isEmpty {
            return "‘\(trimmedQuery)’와 일치하는 곡 또는 PDF가 없어요."
        }
        return "검색 조건과 일치하는 악보가 없어요."
    }

    private func searchResultSummary(for song: Song) -> String {
        let keyNames = Set(
            song.sheets?.compactMap { $0.musicalKey?.displayName } ?? []
        ).sorted()
        let fileNames = PDFFileNameSearch.names(for: song)

        let keySummary = switch keyNames.count {
        case 0:
            "키 미지정"
        case 1...2:
            keyNames.joined(separator: " · ")
        default:
            "\(keyNames[0]) 외 \(keyNames.count - 1)개 키"
        }

        let fileSummary = switch fileNames.count {
        case 0:
            "원본 PDF 없음"
        case 1:
            fileNames[0]
        default:
            "\(fileNames[0]) 외 \(fileNames.count - 1)개"
        }

        return "\(keySummary) · \(fileSummary)"
    }

    private func toggleFavorite(for song: Song) {
        let previousValue = song.isFavorite
        song.isFavorite.toggle()

        do {
            try modelContext.save()
        } catch {
            song.isFavorite = previousValue
            favoriteSaveErrorMessage = error.localizedDescription
        }
    }

    private func resetSearch() {
        query = ""
        committedQuery = ""
        matchingSongIDs = []
        searchRefreshID = UUID()
    }

    private func refreshSearch(
        for request: SongSearchRefreshRequest
    ) async {
        do {
            try await SearchQueryDebounce.waitIfNeeded(
                pendingQuery: request.query,
                committedQuery: committedQuery
            )
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        let requestFilter = SongSearchFilter(
            query: request.query
        )
        let matches = SongSearchMatcher.filter(
            songs,
            using: requestFilter
        )

        guard !Task.isCancelled else { return }
        matchingSongIDs = matches.map(\.id)
        committedQuery = request.query
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .modelContainer(AppModelContainer.preview)
}
