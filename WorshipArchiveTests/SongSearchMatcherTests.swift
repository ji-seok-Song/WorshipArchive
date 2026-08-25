import XCTest
@testable import WorshipArchive

final class SongSearchMatcherTests: XCTestCase {
    func testMatchesTitleSubstring() {
        let song = Song(title: "예수 열방의 소망")

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "열방의")
        ))
    }

    func testMatchesPDFFileNameAndSeparatorWords() throws {
        let models = try makeSong(
            title: "주의 이름 높이며",
            fileName: "25_09_06_Byhim 콘티🩵.pdf"
        )

        XCTAssertTrue(SongSearchMatcher.matches(
            models.song,
            filter: SongSearchFilter(query: "byhim 콘티")
        ))
        XCTAssertTrue(SongSearchMatcher.matches(
            models.song,
            filter: SongSearchFilter(query: "25 09 06")
        ))
    }

    func testDoesNotSearchLegacyLyricsOrNotes() {
        let song = Song(title: "다른 제목", notes: "검색에서 제외할 메모")
        song.lyricsText = "검색에서 제외할 가사"

        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "제외할 가사")
        ))
        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "제외할 메모")
        ))
    }

    func testFiltersSongsByKey() throws {
        let gSong = try makeSong(
            title: "G키 찬양",
            fileName: "g-score.pdf",
            musicalKey: .gMajor
        ).song
        let aSong = try makeSong(
            title: "A키 찬양",
            fileName: "a-score.pdf",
            musicalKey: .aMajor
        ).song

        let matches = SongSearchMatcher.filter(
            [aSong, gSong],
            using: SongSearchFilter(musicalKey: .gMajor)
        )

        XCTAssertEqual(matches.map(\.id), [gSong.id])
    }

    func testCombinesTitlePDFKeyAndFavoriteFilters() throws {
        let matchingSong = try makeSong(
            title: "은혜 아니면",
            fileName: "청년부_콘티.pdf",
            musicalKey: .gMajor,
            isFavorite: true
        ).song
        let wrongKeySong = try makeSong(
            title: "은혜로다",
            fileName: "청년부_콘티.pdf",
            musicalKey: .aMajor,
            isFavorite: true
        ).song
        let notFavoriteSong = try makeSong(
            title: "은혜",
            fileName: "청년부_콘티.pdf",
            musicalKey: .gMajor,
            isFavorite: false
        ).song
        let filter = SongSearchFilter(
            query: "청년부 콘티",
            musicalKey: .gMajor,
            favoritesOnly: true
        )

        let matches = SongSearchMatcher.filter(
            [wrongKeySong, matchingSong, notFavoriteSong],
            using: filter
        )

        XCTAssertEqual(matches.map(\.id), [matchingSong.id])
    }

    func testCachedPDFNameRefreshesWhenDocumentNameChanges() throws {
        let models = try makeSong(
            title: "파일명 변경",
            fileName: "이전_콘티.pdf"
        )
        let cache = SongSearchTextCache(maximumEntryCount: 4)

        XCTAssertTrue(SongSearchMatcher.matches(
            models.song,
            filter: SongSearchFilter(query: "이전 콘티"),
            searchTextCache: cache
        ))

        models.document.originalFileName = "새로운_콘티.pdf"

        XCTAssertFalse(SongSearchMatcher.matches(
            models.song,
            filter: SongSearchFilter(query: "이전 콘티"),
            searchTextCache: cache
        ))
        XCTAssertTrue(SongSearchMatcher.matches(
            models.song,
            filter: SongSearchFilter(query: "새로운 콘티"),
            searchTextCache: cache
        ))
    }

    func testCachedFirstEvaluationPreservesOriginalResultOrder() {
        let cache = SongSearchTextCache(maximumEntryCount: 1)
        let first = Song(title: "첫째 은혜")
        let second = Song(title: "둘째 은혜")
        let filter = SongSearchFilter(query: "은혜")

        _ = SongSearchMatcher.matches(
            second,
            filter: filter,
            searchTextCache: cache
        )
        let results = SongSearchMatcher.filter(
            [first, second],
            using: filter,
            searchTextCache: cache
        )

        XCTAssertEqual(results.map(\.id), [first.id, second.id])
        XCTAssertEqual(cache.cachedEntryCount, 1)
    }

    func testSearchTextCacheNeverExceedsConfiguredEntryLimit() {
        let cache = SongSearchTextCache(maximumEntryCount: 2)
        let first = Song(title: "첫째")
        let second = Song(title: "둘째")
        let third = Song(title: "셋째")
        let query = SongSearchFilter(query: "없는 단서")

        _ = SongSearchMatcher.matches(first, filter: query, searchTextCache: cache)
        _ = SongSearchMatcher.matches(second, filter: query, searchTextCache: cache)
        _ = SongSearchMatcher.matches(third, filter: query, searchTextCache: cache)

        XCTAssertEqual(cache.cachedEntryCount, 2)
        XCTAssertFalse(cache.contains(songID: first.id))
        XCTAssertTrue(cache.contains(songID: second.id))
        XCTAssertTrue(cache.contains(songID: third.id))
    }

    private func makeSong(
        title: String,
        fileName: String,
        musicalKey: MusicalKey = .cMajor,
        isFavorite: Bool = false
    ) throws -> (
        document: ArchiveDocument,
        song: Song,
        sheet: SongSheet
    ) {
        let document = ArchiveDocument(
            originalFileName: fileName,
            storedFileName: "\(UUID().uuidString).pdf",
            pageCount: 1,
            fileSize: 1,
            checksum: UUID().uuidString
        )
        let song = Song(title: title, isFavorite: isFavorite)
        let sheet = try SongSheet.create(
            startPageIndex: 0,
            endPageIndex: 0,
            musicalKey: musicalKey,
            document: document,
            song: song
        )
        song.sheets = [sheet]
        document.sheets = [sheet]
        return (document, song, sheet)
    }
}
