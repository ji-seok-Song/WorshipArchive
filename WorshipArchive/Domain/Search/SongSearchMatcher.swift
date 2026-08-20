import Foundation

nonisolated struct SongSearchFilter: Equatable, Sendable {
    let query: String
    let musicalKey: MusicalKey?
    let favoritesOnly: Bool
    let performanceDateRange: PerformanceDateRange?
    let serviceType: String

    init(
        query: String = "",
        musicalKey: MusicalKey? = nil,
        favoritesOnly: Bool = false,
        performanceDateRange: PerformanceDateRange? = nil,
        serviceType: String = ""
    ) {
        self.query = SearchTextNormalizer.normalize(query)
        self.musicalKey = musicalKey
        self.favoritesOnly = favoritesOnly
        self.performanceDateRange = performanceDateRange
        self.serviceType = SearchTextNormalizer.normalize(serviceType)
    }
}

@MainActor
enum SongSearchMatcher {
    static func matches(
        _ song: Song,
        filter: SongSearchFilter
    ) -> Bool {
        guard !filter.favoritesOnly || song.isFavorite else {
            return false
        }

        if let musicalKey = filter.musicalKey {
            let hasMatchingSheet = song.sheets?.contains { sheet in
                sheet.musicalKey == musicalKey
            } ?? false
            guard hasMatchingSheet else { return false }
        }

        if filter.performanceDateRange != nil || !filter.serviceType.isEmpty {
            let hasMatchingPerformance = song.performanceRecords?.contains { record in
                let isWithinDateRange = filter.performanceDateRange?.contains(record.performedAt) ?? true
                let hasMatchingServiceType = filter.serviceType.isEmpty
                    || SearchTextNormalizer.normalize(record.serviceType) == filter.serviceType
                return isWithinDateRange && hasMatchingServiceType
            } ?? false
            guard hasMatchingPerformance else { return false }
        }

        guard !filter.query.isEmpty else { return true }

        return [
            song.normalizedTitle,
            SearchTextNormalizer.normalize(song.lyricsText),
            SearchTextNormalizer.normalize(song.notes)
        ].contains { searchableText in
            searchableText.contains(filter.query)
        }
    }

    static func filter(
        _ songs: [Song],
        using filter: SongSearchFilter
    ) -> [Song] {
        songs.filter { matches($0, filter: filter) }
    }
}
