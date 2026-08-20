import Foundation

nonisolated struct PerformanceRecordDraft: Equatable, Sendable {
    let id: UUID
    let performedAt: Date
    let serviceType: String
    let leader: String
    let musicalKey: MusicalKey?
    let notes: String

    init(
        id: UUID = UUID(),
        performedAt: Date,
        serviceType: String,
        leader: String = "",
        musicalKey: MusicalKey? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.performedAt = performedAt
        self.serviceType = serviceType.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.leader = leader.trimmingCharacters(in: .whitespacesAndNewlines)
        self.musicalKey = musicalKey
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
