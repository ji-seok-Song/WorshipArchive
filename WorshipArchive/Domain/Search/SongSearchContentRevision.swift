import Foundation

nonisolated struct SongSearchContentRevision: Equatable, Sendable {
    let songID: UUID
    let normalizedTitle: String
    let lyricsText: String
    let notes: String
    let isFavorite: Bool

    @MainActor
    static func capture(_ songs: [Song]) -> [SongSearchContentRevision] {
        songs.map { song in
            SongSearchContentRevision(
                songID: song.id,
                normalizedTitle: song.normalizedTitle,
                lyricsText: song.lyricsText,
                notes: song.notes,
                isFavorite: song.isFavorite
            )
        }
        .sorted { lhs, rhs in
            lhs.songID.uuidString < rhs.songID.uuidString
        }
    }
}

nonisolated struct SongSearchRefreshRequest: Equatable, Sendable {
    let query: String
    let contentRevisions: [SongSearchContentRevision]
    let refreshID: UUID
}
