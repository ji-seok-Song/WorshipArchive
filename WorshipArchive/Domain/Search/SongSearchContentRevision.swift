import Foundation

nonisolated struct SongSearchSheetRevision: Equatable, Sendable {
    let id: UUID
    let keyRawValue: String
    let pdfFileName: String
}

nonisolated struct SongSearchContentRevision: Equatable, Sendable {
    let songID: UUID
    let normalizedTitle: String
    let isFavorite: Bool
    let sheets: [SongSearchSheetRevision]

    @MainActor
    static func capture(_ songs: [Song]) -> [SongSearchContentRevision] {
        songs.map { song in
            SongSearchContentRevision(
                songID: song.id,
                normalizedTitle: song.normalizedTitle,
                isFavorite: song.isFavorite,
                sheets: (song.sheets ?? [])
                    .map { sheet in
                        SongSearchSheetRevision(
                            id: sheet.id,
                            keyRawValue: sheet.keyRawValue,
                            pdfFileName: sheet.document?.originalFileName ?? ""
                        )
                    }
                    .sorted { lhs, rhs in
                        lhs.id.uuidString < rhs.id.uuidString
                    }
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
