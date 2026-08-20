import Foundation

nonisolated struct SongSearchFilter: Equatable, Sendable {
    let query: String
    let musicalKey: MusicalKey?
    let favoritesOnly: Bool

    init(
        query: String = "",
        musicalKey: MusicalKey? = nil,
        favoritesOnly: Bool = false
    ) {
        self.query = SearchTextNormalizer.normalize(query)
        self.musicalKey = musicalKey
        self.favoritesOnly = favoritesOnly
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
