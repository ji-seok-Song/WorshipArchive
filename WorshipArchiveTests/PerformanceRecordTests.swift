import SwiftData
import XCTest
@testable import WorshipArchive

final class PerformanceRecordTests: XCTestCase {
    func testDraftTrimsServiceTypeAndOptionalText() {
        let draft = PerformanceRecordDraft(
            performedAt: Date(),
            serviceType: "  주일 2부 예배\n",
            leader: "  홍길동 ",
            notes: "\n  첫 곡  "
        )

        XCTAssertEqual(draft.serviceType, "주일 2부 예배")
        XCTAssertEqual(draft.leader, "홍길동")
        XCTAssertEqual(draft.notes, "첫 곡")
    }

    @MainActor
    func testAddPersistsTrimmedDraftAndRetryDoesNotDuplicate() throws {
        let setup = try makeContextWithSong()
        let id = UUID()
        let performedAt = Date(timeIntervalSince1970: 1_000)
        let draft = PerformanceRecordDraft(
            id: id,
            performedAt: performedAt,
            serviceType: "  수요 예배  ",
            leader: "인도자",
            musicalKey: .gMajor,
            notes: "후렴부터"
        )

        let first = try PerformanceRecordPersistence.add(
            draft,
            to: setup.song,
            in: setup.context
        )
        let retried = try PerformanceRecordPersistence.add(
            draft,
            to: setup.song,
            in: setup.context
        )

        XCTAssertTrue(first === retried)
        let records = try setup.context.fetch(FetchDescriptor<PerformanceRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, id)
        XCTAssertEqual(records.first?.performedAt, performedAt)
        XCTAssertEqual(records.first?.serviceType, "수요 예배")
        XCTAssertEqual(records.first?.leader, "인도자")
        XCTAssertEqual(records.first?.musicalKey, .gMajor)
        XCTAssertEqual(records.first?.notes, "후렴부터")
        XCTAssertEqual(records.first?.song?.id, setup.song.id)
    }

    @MainActor
    func testAddRejectsBlankServiceType() throws {
        let setup = try makeContextWithSong()
        let draft = PerformanceRecordDraft(
            performedAt: Date(),
            serviceType: " \n "
        )

        XCTAssertThrowsError(
            try PerformanceRecordPersistence.add(
                draft,
                to: setup.song,
                in: setup.context
            )
        ) { error in
            XCTAssertEqual(
                error as? PerformanceRecordPersistenceError,
                .emptyServiceType
            )
        }
        XCTAssertTrue(
            try setup.context.fetch(FetchDescriptor<PerformanceRecord>()).isEmpty
        )
    }

    @MainActor
    func testAddFailureRemovesPendingRecordBeforeLaterSave() throws {
        let setup = try makeContextWithSong()
        let draft = PerformanceRecordDraft(
            performedAt: Date(),
            serviceType: "주일 예배"
        )

        XCTAssertThrowsError(
            try PerformanceRecordPersistence.add(
                draft,
                to: setup.song,
                in: setup.context,
                save: { throw StubSaveError.failed }
            )
        )

        setup.song.notes = "후속 변경"
        try setup.context.save()

        let verificationContext = ModelContext(setup.container)
        let savedSongs = try verificationContext.fetch(FetchDescriptor<Song>())
        let savedRecords = try verificationContext.fetch(
            FetchDescriptor<PerformanceRecord>()
        )
        XCTAssertEqual(savedSongs.first?.notes, "후속 변경")
        XCTAssertTrue(savedRecords.isEmpty)
        XCTAssertTrue(setup.song.performanceRecords?.isEmpty ?? true)
    }

    @MainActor
    func testDeleteFailureRestoresRecordBeforeLaterSave() throws {
        let setup = try makeContextWithSong()
        let draft = PerformanceRecordDraft(
            performedAt: Date(),
            serviceType: "새벽 예배"
        )
        let record = try PerformanceRecordPersistence.add(
            draft,
            to: setup.song,
            in: setup.context
        )

        XCTAssertThrowsError(
            try PerformanceRecordPersistence.delete(
                record,
                in: setup.context,
                save: { throw StubSaveError.failed }
            )
        )

        setup.song.notes = "삭제 실패 뒤 변경"
        try setup.context.save()

        let verificationContext = ModelContext(setup.container)
        let savedRecords = try verificationContext.fetch(
            FetchDescriptor<PerformanceRecord>()
        )
        XCTAssertEqual(savedRecords.map(\.id), [draft.id])
        XCTAssertEqual(savedRecords.first?.song?.id, setup.song.id)
    }

    @MainActor
    func testDeletePersistsRemoval() throws {
        let setup = try makeContextWithSong()
        let record = try PerformanceRecordPersistence.add(
            PerformanceRecordDraft(
                performedAt: Date(),
                serviceType: "금요 예배"
            ),
            to: setup.song,
            in: setup.context
        )

        try PerformanceRecordPersistence.delete(
            record,
            in: setup.context
        )

        let verificationContext = ModelContext(setup.container)
        XCTAssertTrue(
            try verificationContext.fetch(
                FetchDescriptor<PerformanceRecord>()
            ).isEmpty
        )
    }

    @MainActor
    private func makeContextWithSong() throws -> (
        container: ModelContainer,
        context: ModelContext,
        song: Song
    ) {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let song = Song(title: "테스트 찬양")
        context.insert(song)
        try context.save()
        return (container, context, song)
    }
}

private enum StubSaveError: Error {
    case failed
}
