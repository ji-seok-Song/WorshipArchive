import XCTest
@testable import WorshipArchive

final class RecentScoreListingTests: XCTestCase {
    @MainActor
    func testListsOpenedScoresNewestFirstAndLimitsResults() throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let first = try makeModels(sheetID: firstID, title: "첫 번째")
        let second = try makeModels(sheetID: secondID, title: "두 번째")
        let third = try makeModels(sheetID: thirdID, title: "세 번째")
        first.sheet.lastOpenedAt = Date(timeIntervalSince1970: 100)
        second.sheet.lastOpenedAt = Date(timeIntervalSince1970: 300)
        third.sheet.lastOpenedAt = Date(timeIntervalSince1970: 200)

        let entries = RecentScoreListing.entries(
            songs: [first.song, second.song, third.song],
            sheets: [first.sheet, second.sheet, third.sheet],
            limit: 2
        )

        XCTAssertEqual(entries.map(\.id), [secondID, thirdID])
    }

    @MainActor
    func testUsesSheetIDAsDeterministicTieBreaker() throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = try makeModels(sheetID: firstID, title: "첫 번째")
        let second = try makeModels(sheetID: secondID, title: "두 번째")
        let openedAt = Date(timeIntervalSince1970: 100)
        first.sheet.lastOpenedAt = openedAt
        second.sheet.lastOpenedAt = openedAt

        let entries = RecentScoreListing.entries(
            songs: [second.song, first.song],
            sheets: [second.sheet, first.sheet]
        )

        XCTAssertEqual(entries.map(\.id), [firstID, secondID])
    }

    @MainActor
    func testExcludesNeverOpenedAndBrokenRelationshipScores() throws {
        let valid = try makeModels(title: "정상")
        let neverOpened = try makeModels(title: "미열람")
        let missingSong = try makeModels(title: "곡 없음")
        let missingDocument = try makeModels(title: "문서 없음")
        let openedAt = Date(timeIntervalSince1970: 100)
        valid.sheet.lastOpenedAt = openedAt
        missingSong.sheet.lastOpenedAt = openedAt
        missingSong.sheet.song = nil
        missingDocument.sheet.lastOpenedAt = openedAt
        missingDocument.sheet.document = nil

        let entries = RecentScoreListing.entries(
            songs: [
                valid.song,
                neverOpened.song,
                missingSong.song,
                missingDocument.song
            ],
            sheets: [
                valid.sheet,
                neverOpened.sheet,
                missingSong.sheet,
                missingDocument.sheet
            ]
        )

        XCTAssertEqual(entries.map(\.id), [valid.sheet.id])
    }

    @MainActor
    func testExcludesSheetWhoseSongWasDeletedFromFetchedResults() throws {
        let models = try makeModels(title: "삭제된 곡")
        models.sheet.lastOpenedAt = Date(timeIntervalSince1970: 100)

        let entries = RecentScoreListing.entries(
            songs: [],
            sheets: [models.sheet]
        )

        XCTAssertTrue(entries.isEmpty)
    }

    @MainActor
    func testExcludesPageRangeThatNoLongerFitsDocument() throws {
        let models = try makeModels(
            title: "범위 오류",
            startPageIndex: 1,
            endPageIndex: 2
        )
        models.sheet.lastOpenedAt = Date(timeIntervalSince1970: 100)
        models.document.pageCount = 2

        let entries = RecentScoreListing.entries(
            songs: [models.song],
            sheets: [models.sheet]
        )

        XCTAssertTrue(entries.isEmpty)
    }

    @MainActor
    func testNonPositiveLimitReturnsNoEntries() throws {
        let models = try makeModels(title: "제한")
        models.sheet.lastOpenedAt = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(RecentScoreListing.entries(
            songs: [models.song],
            sheets: [models.sheet],
            limit: 0
        ).isEmpty)
    }

    @MainActor
    private func makeModels(
        sheetID: UUID = UUID(),
        title: String,
        startPageIndex: Int = 0,
        endPageIndex: Int = 1
    ) throws -> (
        document: ArchiveDocument,
        song: Song,
        sheet: SongSheet
    ) {
        let document = ArchiveDocument(
            originalFileName: "score.pdf",
            storedFileName: "stored.pdf",
            pageCount: 3,
            fileSize: 100,
            checksum: "checksum"
        )
        let song = Song(title: title)
        let sheet = try SongSheet.create(
            id: sheetID,
            startPageIndex: startPageIndex,
            endPageIndex: endPageIndex,
            document: document,
            song: song
        )
        return (document, song, sheet)
    }
}
