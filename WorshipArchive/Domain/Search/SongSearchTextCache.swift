import Foundation

nonisolated struct SongSearchableText: Equatable, Sendable {
    let title: String
    let lyrics: String
    let notes: String

    func contains(_ query: String) -> Bool {
        title.contains(query)
            || lyrics.contains(query)
            || notes.contains(query)
    }
}

@MainActor
final class SongSearchTextCache {
    nonisolated static let defaultMaximumEntryCount = 512

    private struct SourceSnapshot: Equatable {
        let normalizedTitle: String
        let lyricsText: String
        let notes: String
    }

    private struct Entry {
        let source: SourceSnapshot
        let searchableText: SongSearchableText
    }

    let maximumEntryCount: Int

    private var entries: [UUID: Entry] = [:]
    private var insertionOrder: [UUID] = []
    private var nextEvictionIndex = 0

    init(
        maximumEntryCount: Int = defaultMaximumEntryCount
    ) {
        self.maximumEntryCount = max(1, maximumEntryCount)
        entries.reserveCapacity(self.maximumEntryCount)
        insertionOrder.reserveCapacity(self.maximumEntryCount)
    }

    var cachedEntryCount: Int {
        entries.count
    }

    func contains(songID: UUID) -> Bool {
        entries[songID] != nil
    }

    func searchableText(for song: Song) -> SongSearchableText {
        let source = SourceSnapshot(
            normalizedTitle: song.normalizedTitle,
            lyricsText: song.lyricsText,
            notes: song.notes
        )

        if let cached = entries[song.id], cached.source == source {
            return cached.searchableText
        }

        let searchableText = SongSearchableText(
            title: source.normalizedTitle,
            lyrics: SearchTextNormalizer.normalize(source.lyricsText),
            notes: SearchTextNormalizer.normalize(source.notes)
        )
        store(
            Entry(source: source, searchableText: searchableText),
            for: song.id
        )
        return searchableText
    }

    private func store(_ entry: Entry, for songID: UUID) {
        if entries.updateValue(entry, forKey: songID) != nil {
            return
        }

        if insertionOrder.count < maximumEntryCount {
            insertionOrder.append(songID)
            return
        }

        let evictedSongID = insertionOrder[nextEvictionIndex]
        entries.removeValue(forKey: evictedSongID)
        insertionOrder[nextEvictionIndex] = songID
        nextEvictionIndex = (nextEvictionIndex + 1) % maximumEntryCount
    }
}
