import XCTest
@testable import WorshipArchive

final class SongSearchContentRevisionTests: XCTestCase {
    @MainActor
    func testTitlePDFNameAndKeyChangesInvalidateSearchRequest() throws {
        let models = try makeModels()
        let before = makeRequest(songs: [models.song])

        models.song.rename(to: "바뀐 제목")
        let afterTitle = makeRequest(songs: [models.song])
        models.document.originalFileName = "바뀐_콘티.pdf"
        let afterPDFName = makeRequest(songs: [models.song])
        models.sheet.musicalKey = .aMajor
        let afterKey = makeRequest(songs: [models.song])

        XCTAssertNotEqual(before, afterTitle)
        XCTAssertNotEqual(afterTitle, afterPDFName)
        XCTAssertNotEqual(afterPDFName, afterKey)
    }

    @MainActor
    func testLegacyLyricsAndNotesDoNotInvalidateSearchRequest() throws {
        let models = try makeModels()
        let before = makeRequest(songs: [models.song])

        models.song.lyricsText = "검색에서 제외할 가사"
        models.song.notes = "검색에서 제외할 메모"
        let after = makeRequest(songs: [models.song])

        XCTAssertEqual(before, after)
    }

    @MainActor
    private func makeRequest(
        songs: [Song],
        query: String = "은혜"
    ) -> SongSearchRefreshRequest {
        SongSearchRefreshRequest(
            query: query,
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
            originalFileName: "원본_콘티.pdf",
            storedFileName: "stored.pdf",
            pageCount: 1,
            fileSize: 100,
            checksum: "checksum"
        )
        let song = Song(title: "은혜")
        let sheet = try SongSheet.create(
            startPageIndex: 0,
            endPageIndex: 0,
            musicalKey: .gMajor,
            document: document,
            song: song
        )
        song.sheets = [sheet]
        document.sheets = [sheet]
        return (document, song, sheet)
    }
}
