import Foundation

nonisolated struct SongSearchableText: Equatable, Sendable {
    let title: String
    let pdfFileNames: String

    func contains(_ query: String) -> Bool {
        title.contains(query)
            || pdfFileNames.contains(query)
    }
}

nonisolated final class SongSearchTextCache {
    nonisolated static let defaultMaximumEntryCount = 512

    private struct SourceSnapshot: Equatable {
        let normalizedTitle: String
        let pdfFileNames: [String]
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

    @MainActor
    var cachedEntryCount: Int {
        entries.count
    }

    @MainActor
    func contains(songID: UUID) -> Bool {
        entries[songID] != nil
    }

    @MainActor
    func searchableText(for song: Song) -> SongSearchableText {
        let source = SourceSnapshot(
            normalizedTitle: song.normalizedTitle,
            pdfFileNames: PDFFileNameSearch.names(for: song)
        )

        if let cached = entries[song.id], cached.source == source {
            return cached.searchableText
        }

        let searchableText = SongSearchableText(
            title: source.normalizedTitle,
            pdfFileNames: source.pdfFileNames
                .flatMap(PDFFileNameSearch.searchableVariants)
                .joined(separator: " ")
        )
        store(
            Entry(source: source, searchableText: searchableText),
            for: song.id
        )
        return searchableText
    }

    @MainActor
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

nonisolated enum PDFFileNameSearch {
    static func names(for song: Song) -> [String] {
        Array(Set(
            song.sheets?.compactMap { sheet in
                sheet.document?.originalFileName
            } ?? []
        ))
        .sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    static func searchableVariants(for fileName: String) -> [String] {
        let normalized = SearchTextNormalizer.normalize(fileName)
        let words = SearchTextNormalizer.normalize(
            fileName.replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        )
        return normalized == words ? [normalized] : [normalized, words]
    }
}
