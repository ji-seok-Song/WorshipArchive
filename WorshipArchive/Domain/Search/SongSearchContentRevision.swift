import Foundation

nonisolated struct SongSearchSheetRevision: Equatable, Sendable {
    let id: UUID
    let keyRawValue: String
}

nonisolated struct SongSearchPerformanceRevision: Equatable, Sendable {
    let id: UUID
    let performedAt: Date
    let serviceType: String
}

nonisolated struct SongSearchContentRevision: Equatable, Sendable {
    let songID: UUID
    let normalizedTitle: String
    let lyricsText: String
    let notes: String
    let isFavorite: Bool
    let sheets: [SongSearchSheetRevision]
    let performanceRecords: [SongSearchPerformanceRevision]

    @MainActor
    static func capture(_ songs: [Song]) -> [SongSearchContentRevision] {
        songs.map { song in
            SongSearchContentRevision(
                songID: song.id,
                normalizedTitle: song.normalizedTitle,
                lyricsText: song.lyricsText,
                notes: song.notes,
                isFavorite: song.isFavorite,
                sheets: (song.sheets ?? [])
                    .map { sheet in
                        SongSearchSheetRevision(
                            id: sheet.id,
                            keyRawValue: sheet.keyRawValue
                        )
                    }
                    .sorted { lhs, rhs in
                        lhs.id.uuidString < rhs.id.uuidString
                    },
                performanceRecords: (song.performanceRecords ?? [])
                    .map { record in
                        SongSearchPerformanceRevision(
                            id: record.id,
                            performedAt: record.performedAt,
                            serviceType: record.serviceType
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
    let selectedKey: MusicalKey?
    let usesPerformanceDateFilter: Bool
    let performanceStartDate: Date
    let performanceEndDate: Date
    let selectedServiceType: String
    let contentRevisions: [SongSearchContentRevision]
    let refreshID: UUID
}
