import Foundation
import SwiftData

@MainActor
enum PerformanceRecordPersistence {
    static func add(
        _ draft: PerformanceRecordDraft,
        to song: Song,
        in context: ModelContext
    ) throws -> PerformanceRecord {
        try add(
            draft,
            to: song,
            in: context,
            save: context.save
        )
    }

    static func delete(
        _ record: PerformanceRecord,
        in context: ModelContext
    ) throws {
        try delete(
            record,
            in: context,
            save: context.save
        )
    }

    static func add(
        _ draft: PerformanceRecordDraft,
        to song: Song,
        in context: ModelContext,
        save: () throws -> Void
    ) throws -> PerformanceRecord {
        guard !draft.serviceType.isEmpty else {
            throw PerformanceRecordPersistenceError.emptyServiceType
        }

        if let existingRecord = try record(withID: draft.id, in: context) {
            guard existingRecord.song?.id == song.id else {
                throw PerformanceRecordPersistenceError.identifierConflict
            }
            return existingRecord
        }

        let previousRecords = song.performanceRecords
        let record = PerformanceRecord(
            id: draft.id,
            performedAt: draft.performedAt,
            serviceType: draft.serviceType,
            leader: draft.leader,
            musicalKey: draft.musicalKey,
            notes: draft.notes,
            song: song
        )
        context.insert(record)

        do {
            try save()
            return record
        } catch {
            record.song = nil
            song.performanceRecords = previousRecords
            context.delete(record)
            throw error
        }
    }

    static func delete(
        _ record: PerformanceRecord,
        in context: ModelContext,
        save: () throws -> Void
    ) throws {
        context.delete(record)

        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func record(
        withID id: UUID,
        in context: ModelContext
    ) throws -> PerformanceRecord? {
        var descriptor = FetchDescriptor<PerformanceRecord>(
            predicate: #Predicate { record in
                record.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

enum PerformanceRecordPersistenceError: LocalizedError, Equatable {
    case emptyServiceType
    case identifierConflict

    var errorDescription: String? {
        switch self {
        case .emptyServiceType:
            "예배 종류를 입력해 주세요."
        case .identifierConflict:
            "같은 기록 식별자가 다른 곡에서 이미 사용 중입니다."
        }
    }
}
