import XCTest
@testable import WorshipArchive

final class SongSearchContentRevisionTests: XCTestCase {
    @MainActor
    func testSearchableContentChangeInvalidatesSameQueryRequest() {
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
}
