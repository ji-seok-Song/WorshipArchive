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
    private static let sharedSearchTextCache = SongSearchTextCache()

    static func matches(
        _ song: Song,
        filter: SongSearchFilter
    ) -> Bool {
        matches(
            song,
            filter: filter,
            searchTextCache: sharedSearchTextCache
        )
    }

    static func matches(
        _ song: Song,
        filter: SongSearchFilter,
        searchTextCache: SongSearchTextCache
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

        return searchTextCache
            .searchableText(for: song)
            .contains(filter.query)
    }

    static func filter(
        _ songs: [Song],
        using filter: SongSearchFilter
    ) -> [Song] {
        Self.filter(
            songs,
            using: filter,
            searchTextCache: sharedSearchTextCache
        )
    }

    static func filter(
        _ songs: [Song],
        using filter: SongSearchFilter,
        searchTextCache: SongSearchTextCache
    ) -> [Song] {
        guard !filter.query.isEmpty else {
            return songs.filter {
                matches(
                    $0,
                    filter: filter,
                    searchTextCache: searchTextCache
                )
            }
        }

        let cachedSongs = songs.filter {
            searchTextCache.contains(songID: $0.id)
        }
        let uncachedSongs = songs.filter {
            !searchTextCache.contains(songID: $0.id)
        }
        var matchingSongIDs: Set<UUID> = []
        matchingSongIDs.reserveCapacity(songs.count)

        for song in cachedSongs + uncachedSongs where matches(
            song,
            filter: filter,
            searchTextCache: searchTextCache
        ) {
            matchingSongIDs.insert(song.id)
        }

        return songs.filter { matchingSongIDs.contains($0.id) }
    }
}
