import Foundation
import SwiftData

@Model
final class PerformanceRecord {
    var id: UUID = UUID()
    var performedAt: Date = Date()
    var serviceType: String = ""
    var leader: String = ""
    var keyRawValue: String = ""
    var notes: String = ""
    var song: Song?

    init(
        id: UUID = UUID(),
        performedAt: Date,
        serviceType: String = "",
        leader: String = "",
        musicalKey: MusicalKey? = nil,
        notes: String = "",
        song: Song
    ) {
        self.id = id
        self.performedAt = performedAt
        self.serviceType = serviceType
        self.leader = leader
        keyRawValue = musicalKey?.rawValue ?? ""
        self.notes = notes
        self.song = song
    }

    var musicalKey: MusicalKey? {
        get { MusicalKey(rawValue: keyRawValue)?.pitchOnly }
        set { keyRawValue = newValue?.rawValue ?? "" }
    }
}
