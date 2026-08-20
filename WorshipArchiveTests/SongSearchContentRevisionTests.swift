import XCTest
@testable import WorshipArchive

final class SongSearchContentRevisionTests: XCTestCase {
    @MainActor
    func testRawTextChangeInvalidatesSameFilterRequestAndMatcherResult() {
        let song = Song(
            title: "원래 제목",
            lyricsText: "기존 가사",
            notes: "기존 메모"
        )
        let filter = SongSearchFilter(query: "새 단서")
        let cache = SongSearchTextCache(maximumEntryCount: 4)
        let before = makeRequest(songs: [song], query: "새 단서")

        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: filter,
            searchTextCache: cache
        ))

        song.lyricsText = "새 단서가 들어간 가사"
        let afterLyrics = makeRequest(songs: [song], query: "새 단서")

        XCTAssertNotEqual(before, afterLyrics)
        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: filter,
            searchTextCache: cache
        ))

        song.notes = "새로 바뀐 메모"
        let afterNotes = makeRequest(songs: [song], query: "새 단서")
        song.rename(to: "바뀐 제목")
        let afterTitle = makeRequest(songs: [song], query: "새 단서")
        song.isFavorite = true
        let afterFavorite = makeRequest(songs: [song], query: "새 단서")

        XCTAssertNotEqual(afterLyrics, afterNotes)
        XCTAssertNotEqual(afterNotes, afterTitle)
        XCTAssertNotEqual(afterTitle, afterFavorite)
    }

    @MainActor
    func testSheetKeyChangeInvalidatesSameFilterRequest() throws {
        let models = try makeModels()
        let before = makeRequest(songs: [models.song])

        models.sheet.musicalKey = .aMajor
        let after = makeRequest(songs: [models.song])

        XCTAssertNotEqual(before, after)
    }

    @MainActor
    func testPerformanceSearchValuesInvalidateSameFilterRequest() throws {
        let models = try makeModels()
        let record = PerformanceRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            performedAt: Date(timeIntervalSince1970: 100),
            serviceType: "주일 예배",
            song: models.song
        )
        models.song.performanceRecords = [record]
        let before = makeRequest(songs: [models.song])

        record.performedAt = Date(timeIntervalSince1970: 200)
        let afterDate = makeRequest(songs: [models.song])
        record.serviceType = "청년 예배"
        let afterService = makeRequest(songs: [models.song])

        XCTAssertNotEqual(before, afterDate)
        XCTAssertNotEqual(afterDate, afterService)
    }

    @MainActor
    func testRelationshipOrderingDoesNotChangeRequestIdentity() throws {
        let models = try makeModels()
        let otherSheet = try SongSheet.create(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            startPageIndex: 1,
            endPageIndex: 1,
            musicalKey: .aMajor,
            document: models.document,
            song: models.song
        )
        let firstRecord = PerformanceRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            performedAt: Date(timeIntervalSince1970: 100),
            serviceType: "주일 예배",
            song: models.song
        )
        let secondRecord = PerformanceRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            performedAt: Date(timeIntervalSince1970: 200),
            serviceType: "청년 예배",
            song: models.song
        )
        models.song.sheets = [otherSheet, models.sheet]
        models.song.performanceRecords = [secondRecord, firstRecord]
        let firstOrder = makeRequest(songs: [models.song])

        models.song.sheets = [models.sheet, otherSheet]
        models.song.performanceRecords = [firstRecord, secondRecord]
        let reversedOrder = makeRequest(songs: [models.song])

        XCTAssertEqual(firstOrder, reversedOrder)
    }

    @MainActor
    private func makeRequest(
        songs: [Song],
        query: String = "은혜"
    ) -> SongSearchRefreshRequest {
        SongSearchRefreshRequest(
            query: query,
            selectedKey: .gMajor,
            usesPerformanceDateFilter: false,
            performanceStartDate: Date(timeIntervalSince1970: 0),
            performanceEndDate: Date(timeIntervalSince1970: 1_000),
            selectedServiceType: "",
            contentRevisions: SongSearchContentRevision.capture(songs),
            refreshID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        )
    }

    @MainActor
    private func makeModels() throws -> (
        document: ArchiveDocument,
        song: Song,
        sheet: SongSheet
    ) {
        let document = ArchiveDocument(
            originalFileName: "score.pdf",
            storedFileName: "stored.pdf",
            pageCount: 2,
            fileSize: 100,
            checksum: "checksum"
        )
        let song = Song(title: "은혜")
        let sheet = try SongSheet.create(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            startPageIndex: 0,
            endPageIndex: 0,
            musicalKey: .gMajor,
            document: document,
            song: song
        )
        song.sheets = [sheet]
        return (document, song, sheet)
    }
}
