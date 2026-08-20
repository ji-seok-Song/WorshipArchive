import Foundation

@MainActor
struct RecentScoreEntry: Identifiable {
    let sheet: SongSheet
    let song: Song
    let document: ArchiveDocument
    let openedAt: Date

    var id: UUID { sheet.id }

    var scoreSummary: String {
        let keyName = sheet.musicalKey?.displayName ?? "키 미지정"
        let pageDescription: String

        if sheet.startPageIndex == sheet.endPageIndex {
            pageDescription = "\(sheet.startPageIndex + 1)페이지"
        } else {
            pageDescription = "\(sheet.startPageIndex + 1)–\(sheet.endPageIndex + 1)페이지"
        }

        return "\(keyName) · \(pageDescription)"
    }
}

@MainActor
enum RecentScoreListing {
    nonisolated static let defaultLimit = 5

    static func entries(
        songs: [Song],
        sheets: [SongSheet],
        limit: Int = defaultLimit
    ) -> [RecentScoreEntry] {
        guard limit > 0 else { return [] }

        let knownSongIDs = Set(songs.map(\.id))
        let validEntries = sheets.compactMap { sheet -> RecentScoreEntry? in
            guard
                let openedAt = sheet.lastOpenedAt,
                let song = sheet.song,
                knownSongIDs.contains(song.id),
                let document = sheet.document,
                isValid(sheet: sheet, for: document)
            else {
                return nil
            }

            return RecentScoreEntry(
                sheet: sheet,
                song: song,
                document: document,
                openedAt: openedAt
            )
        }

        return Array(validEntries.sorted(by: precedes).prefix(limit))
    }

    private static func isValid(
        sheet: SongSheet,
        for document: ArchiveDocument
    ) -> Bool {
        document.pageCount > 0
            && sheet.startPageIndex >= 0
            && sheet.startPageIndex <= sheet.endPageIndex
            && sheet.endPageIndex < document.pageCount
    }

    private static func precedes(
        _ lhs: RecentScoreEntry,
        _ rhs: RecentScoreEntry
    ) -> Bool {
        if lhs.openedAt != rhs.openedAt {
            return lhs.openedAt > rhs.openedAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
