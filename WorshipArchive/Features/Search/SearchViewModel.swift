import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var favoriteSaveErrorMessage: String?

    private(set) var committedQuery = ""
    private(set) var matchingSongIDs: [UUID] = []

    @ObservationIgnored
    private var searchRefreshID = UUID()

    var shouldShowResults: Bool {
        !SearchTextNormalizer.normalize(query).isEmpty
            || !SearchTextNormalizer.normalize(committedQuery).isEmpty
    }

    var isQueryPending: Bool {
        SearchTextNormalizer.normalize(query)
            != SearchTextNormalizer.normalize(committedQuery)
    }

    func searchRequest(for songs: [Song]) -> SongSearchRefreshRequest {
        SongSearchRefreshRequest(
            query: query,
            contentRevisions: SongSearchContentRevision.capture(songs),
            refreshID: searchRefreshID
        )
    }

    func displayedSongs(from songs: [Song]) -> [Song] {
        let matchingIDs = Set(matchingSongIDs)
        return songs.filter { matchingIDs.contains($0.id) }
    }

    func refreshContent() {
        searchRefreshID = UUID()
    }

    func resetSearch() {
        query = ""
        committedQuery = ""
        matchingSongIDs = []
        refreshContent()
    }

    func refreshSearch(
        for request: SongSearchRefreshRequest,
        songs: [Song]
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

        let matches = SongSearchMatcher.filter(
            songs,
            using: SongSearchFilter(query: request.query)
        )

        guard !Task.isCancelled else { return }
        matchingSongIDs = matches.map(\.id)
        committedQuery = request.query
    }

    func toggleFavorite(for song: Song, in modelContext: ModelContext) {
        let previousValue = song.isFavorite
        song.isFavorite.toggle()

        do {
            try modelContext.save()
        } catch {
            song.isFavorite = previousValue
            favoriteSaveErrorMessage = error.localizedDescription
        }
    }

    func emptyResultMessage() -> String {
        let trimmedQuery = committedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return "검색 조건과 일치하는 악보가 없어요."
        }
        return "‘\(trimmedQuery)’와 일치하는 곡 또는 PDF가 없어요."
    }

    func searchResultSummary(for song: Song) -> String {
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
}
