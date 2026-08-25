import XCTest
@testable import WorshipArchive

final class PreferredSongSheetSelectorTests: XCTestCase {
    @MainActor
    func testSelectsMostRecentlyOpenedSheet() throws {
        let song = Song(title: "최근 악보")
        let older = try makeSheet(
            song: song,
            createdAt: Date(timeIntervalSince1970: 300),
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )
        let recent = try makeSheet(
            song: song,
            createdAt: Date(timeIntervalSince1970: 200),
            lastOpenedAt: Date(timeIntervalSince1970: 400)
        )
        song.sheets = [older, recent]

        XCTAssertEqual(
            PreferredSongSheetSelector.select(for: song)?.id,
            recent.id
        )
    }

    @MainActor
    func testSelectsNewestSheetWhenNoneHasBeenOpened() throws {
        let song = Song(title: "새 악보")
        let older = try makeSheet(
            song: song,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newest = try makeSheet(
            song: song,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        song.sheets = [older, newest]

        XCTAssertEqual(
            PreferredSongSheetSelector.select(for: song)?.id,
            newest.id
        )
    }

    @MainActor
    func testIgnoresMissingAndInvalidDocuments() throws {
        let song = Song(title: "유효한 악보")
        let missingDocument = try makeSheet(
            song: song,
            createdAt: Date(timeIntervalSince1970: 500)
        )
        missingDocument.document = nil

        let invalidDocument = try makeSheet(
            song: song,
            createdAt: Date(timeIntervalSince1970: 400)
        )
        invalidDocument.document?.pageCount = 0

        let valid = try makeSheet(
            song: song,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        song.sheets = [missingDocument, invalidDocument, valid]

        XCTAssertEqual(
            PreferredSongSheetSelector.select(for: song)?.id,
            valid.id
        )
    }

    @MainActor
    private func makeSheet(
        song: Song,
        createdAt: Date,
        lastOpenedAt: Date? = nil
    ) throws -> SongSheet {
        let document = ArchiveDocument(
            originalFileName: "\(UUID().uuidString).pdf",
            storedFileName: "\(UUID().uuidString).pdf",
            pageCount: 1,
            fileSize: 1,
            checksum: UUID().uuidString
        )
        let sheet = try SongSheet.create(
            startPageIndex: 0,
            endPageIndex: 0,
            createdAt: createdAt,
            document: document,
            song: song
        )
        sheet.lastOpenedAt = lastOpenedAt
        return sheet
    }
}
