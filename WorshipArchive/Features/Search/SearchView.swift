import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    @State private var query = ""
    @State private var selectedKey: MusicalKey?
    @State private var favoriteSaveErrorMessage: String?

    let fileAccess: any StoredPDFAccessing

    init(fileAccess: any StoredPDFAccessing = LocalPDFFileStore.live()) {
        self.fileAccess = fileAccess
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                keyFilter

                if shouldShowResults, !filteredSongs.isEmpty {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredSongs, id: \.id) { song in
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
                    searchEmptyState
                }
            }
            .frame(maxWidth: 620)
            .padding()
        }
        .background(ArchiveTheme.background)
        .navigationTitle("검색")
        .searchable(text: $query, prompt: "제목, 가사 또는 메모 검색")
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
        SongSearchFilter(query: query, musicalKey: selectedKey)
    }

    private var filteredSongs: [Song] {
        SongSearchMatcher.filter(songs, using: filter)
    }

    private var shouldShowResults: Bool {
        !filter.query.isEmpty || selectedKey != nil
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

    private var keyFilter: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("키", selection: $selectedKey) {
                    Text("모든 키")
                        .tag(nil as MusicalKey?)

                    ForEach(MusicalKey.allCases) { key in
                        Text(key.displayName)
                            .tag(key as MusicalKey?)
                    }
                }
            } label: {
                Label(
                    selectedKey?.displayName ?? "모든 키",
                    systemImage: "music.quarternote.3"
                )
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("키 필터")
            .accessibilityValue(selectedKey?.displayName ?? "모든 키")

            if selectedKey != nil {
                Button("키 필터 지우기", systemImage: "xmark.circle.fill") {
                    selectedKey = nil
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if shouldShowResults {
                Text("\(filteredSongs.count)곡")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchEmptyState: some View {
        let hasFilter = shouldShowResults

        return ArchiveEmptyState(
            systemImage: hasFilter ? "music.note" : "text.magnifyingglass",
            title: hasFilter ? "검색 결과가 없어요" : "기억나는 단서를 입력해 보세요",
            message: hasFilter
                ? emptyResultMessage
                : "곡 제목, 가사 한 구절, 메모를 검색하고 키로 좁힐 수 있어요."
        )
    }

    private var emptyResultMessage: String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (trimmedQuery.isEmpty, selectedKey) {
        case (false, let key?):
            return "‘\(trimmedQuery)’ 및 \(key.displayName) 키와 일치하는 악보가 없어요."
        case (false, nil):
            return "‘\(trimmedQuery)’와 일치하는 악보가 아직 등록되지 않았어요."
        case (true, let key?):
            return "\(key.displayName) 키로 등록된 악보가 아직 없어요."
        case (true, nil):
            return "검색 조건과 일치하는 악보가 없어요."
        }
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
}

#Preview {
    NavigationStack {
        SearchView()
    }
}
