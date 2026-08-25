import Foundation
import SwiftData

@Model
final class Song {
    var id: UUID = UUID()
    private(set) var title: String = ""
    private(set) var normalizedTitle: String = ""
    // Retained only so existing SwiftData and CloudKit stores remain compatible.
    // New imports do not populate or search this legacy field.
    var lyricsText: String = ""
    var notes: String = ""
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var lastOpenedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SongSheet.song)
    var sheets: [SongSheet]?

    // Retained only for compatibility with stores created before the feature
    // was removed. No user-facing flow creates or displays these records.
    @Relationship(deleteRule: .cascade, inverse: \PerformanceRecord.song)
    var performanceRecords: [PerformanceRecord]?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        normalizedTitle = SearchTextNormalizer.normalize(title)
        self.notes = notes
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    func rename(to newTitle: String) {
        title = newTitle
        normalizedTitle = SearchTextNormalizer.normalize(newTitle)
    }
}
