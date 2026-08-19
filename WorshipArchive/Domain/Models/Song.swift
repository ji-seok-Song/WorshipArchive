import Foundation
import SwiftData

@Model
final class Song {
    var id: UUID = UUID()
    private(set) var title: String = ""
    private(set) var normalizedTitle: String = ""
    var lyricsText: String = ""
    var notes: String = ""
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var lastOpenedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SongSheet.song)
    var sheets: [SongSheet]?

    @Relationship(deleteRule: .cascade, inverse: \PerformanceRecord.song)
    var performanceRecords: [PerformanceRecord]?

    init(
        id: UUID = UUID(),
        title: String,
        lyricsText: String = "",
        notes: String = "",
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        normalizedTitle = SearchTextNormalizer.normalize(title)
        self.lyricsText = lyricsText
        self.notes = notes
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    func rename(to newTitle: String) {
        title = newTitle
        normalizedTitle = SearchTextNormalizer.normalize(newTitle)
    }
}
