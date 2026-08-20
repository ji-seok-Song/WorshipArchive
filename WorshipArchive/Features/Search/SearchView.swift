import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    @State private var query = ""
    @State private var selectedKey: MusicalKey?
    @State private var usesPerformanceDateFilter = false
    @State private var performanceStartDate: Date
    @State private var performanceEndDate: Date
    @State private var selectedServiceType = ""
    @State private var favoriteSaveErrorMessage: String?

    let fileAccess: any StoredPDFAccessing

    init(fileAccess: any StoredPDFAccessing = LocalPDFFileStore.live()) {
        self.fileAccess = fileAccess
        let today = Date()
        _performanceStartDate = State(
            initialValue: Calendar.current.date(
                byAdding: .month,
                value: -1,
                to: today
            ) ?? today
        )
        _performanceEndDate = State(initialValue: today)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                filterPanel

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
        SongSearchFilter(
            query: query,
            musicalKey: selectedKey,
            performanceDateRange: performanceDateRange,
            serviceType: selectedServiceType
        )
    }

    private var performanceDateRange: PerformanceDateRange? {
        guard usesPerformanceDateFilter else { return nil }

        return try? PerformanceDateRange(
            startDate: performanceStartDate,
            endDate: performanceEndDate,
            calendar: .current
        )
    }

    private var filteredSongs: [Song] {
        SongSearchMatcher.filter(songs, using: filter)
    }

    private var shouldShowResults: Bool {
        !filter.query.isEmpty
            || selectedKey != nil
            || usesPerformanceDateFilter
            || !selectedServiceType.isEmpty
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

    private var filterPanel: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    keyMenu
                    serviceTypeMenu
                    Spacer(minLength: 0)
                    resultCount
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        keyMenu
                        serviceTypeMenu
                    }
                    resultCount
                }
            }

            Toggle(isOn: $usesPerformanceDateFilter) {
                Label("연주 날짜로 찾기", systemImage: "calendar")
            }

            if usesPerformanceDateFilter {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        startDatePicker
                        endDatePicker
                    }

                    VStack(spacing: 12) {
                        startDatePicker
                        endDatePicker
                    }
                }
            }

            if shouldShowResults {
                Button("필터 초기화", systemImage: "arrow.counterclockwise") {
                    resetFilters()
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .background(ArchiveTheme.surface, in: .rect(cornerRadius: 16))
    }

    private var keyMenu: some View {
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
    }

    private var serviceTypeMenu: some View {
        Menu {
            Picker("예배 종류", selection: $selectedServiceType) {
                Text("모든 예배")
                    .tag("")

                ForEach(availableServiceTypes, id: \.self) { serviceType in
                    Text(serviceType)
                        .tag(serviceType)
                }
            }
        } label: {
            Label(
                selectedServiceType.isEmpty ? "모든 예배" : selectedServiceType,
                systemImage: "person.2"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("예배 종류 필터")
        .accessibilityValue(selectedServiceType.isEmpty ? "모든 예배" : selectedServiceType)
        .disabled(availableServiceTypes.isEmpty)
    }

    private var resultCount: some View {
        Text(shouldShowResults ? "\(filteredSongs.count)곡" : "전체 \(songs.count)곡")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var startDatePicker: some View {
        DatePicker(
            "시작",
            selection: $performanceStartDate,
            in: ...performanceEndDate,
            displayedComponents: .date
        )
    }

    private var endDatePicker: some View {
        DatePicker(
            "종료",
            selection: $performanceEndDate,
            in: performanceStartDate...,
            displayedComponents: .date
        )
    }

    private var availableServiceTypes: [String] {
        Set(
            songs.flatMap { song in
                (song.performanceRecords ?? []).compactMap { record in
                    let value = record.serviceType.trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
            }
        ).sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
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

        if usesPerformanceDateFilter || !selectedServiceType.isEmpty {
            return "선택한 연주 기록 조건과 일치하는 악보가 없어요."
        }

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

    private func resetFilters() {
        query = ""
        selectedKey = nil
        usesPerformanceDateFilter = false
        selectedServiceType = ""

        let today = Date()
        performanceStartDate = Calendar.current.date(
            byAdding: .month,
            value: -1,
            to: today
        ) ?? today
        performanceEndDate = today
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}
