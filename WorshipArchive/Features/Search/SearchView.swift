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
                        message: "PDF를 한 번 등록하면 곡 제목, 가사와 메모로 빠르게 찾을 수 있어요.",
                        actionTitle: "첫 PDF 추가",
                        actionSystemImage: "plus",
                        action: addPDF
                    )
                } else if isQueryPending {
                    ProgressView("검색 중…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                } else if showsResults, !displayedSongs.isEmpty {
                    HStack {
                        Text("검색 결과")
                            .font(.headline)

                        Spacer()

                        Text("\(displayedSongs.count)곡")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(displayedSongs, id: \.id) { song in
                            SongLibraryRow(
                                title: song.title,
                                subtitle: keySummary(for: song),
                                isFavorite: song.isFavorite,
                                toggleFavorite: {
                                    toggleFavorite(for: song)
                                }
                            ) {
                                SongDetailView(song: song, fileAccess: fileAccess)
                            }
                        }
                    }
                } else {
                    searchEmptyState(hasQuery: showsResults)
                }
            }
            .frame(maxWidth: 760)
            .padding()
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchiveTheme.background)
        .navigationTitle("검색")
        .searchable(text: $query, prompt: "제목, 가사 또는 메모 검색")
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
        SongSearchFilter(query: committedQuery)
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

    private func searchEmptyState(hasQuery: Bool) -> some View {
        ArchiveEmptyState(
            systemImage: hasQuery ? "music.note" : "text.magnifyingglass",
            title: hasQuery ? "검색 결과가 없어요" : "기억나는 단서를 입력해 보세요",
            message: hasQuery
                ? emptyResultMessage
                : "곡 제목, 가사 한 구절 또는 메모를 검색해 보세요."
        )
    }

    private var emptyResultMessage: String {
        let trimmedQuery = committedQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedQuery.isEmpty {
            return "‘\(trimmedQuery)’와 일치하는 악보가 아직 등록되지 않았어요."
        }
        return "검색어와 일치하는 악보가 없어요."
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

        let requestFilter = SongSearchFilter(query: request.query)
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
