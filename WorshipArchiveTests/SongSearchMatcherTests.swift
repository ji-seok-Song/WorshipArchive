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

    func testMatchesLyricsPhrase() {
        let song = Song(
            title: "주의 이름 높이며",
            lyricsText: "온 세상 위하여 나 복음 전하리"
        )

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "복음 전하리")
        ))
    }

    func testMatchesUserNotes() {
        let song = Song(
            title: "주 사랑이 나를 숨쉬게 해",
            notes: "청년 예배에서 마지막 곡으로 사용"
        )

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "마지막 곡")
        ))
    }

    func testNormalizesWhitespaceInQueryAndSearchableText() {
        let song = Song(
            title: "주의 은혜",
            lyricsText: "영원히\n    주를   찬양해"
        )

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "  영원히   주를\n찬양해  ")
        ))
    }

    func testMatchesCaseAndCharacterWidthInsensitively() {
        let song = Song(title: "ＪＥＳＵＳ　ＬＯＶＥ")

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "jesus love")
        ))
    }

    func testCachedLyricsRefreshWhenSourceLyricsChange() {
        let song = Song(title: "가사 수정", lyricsText: "첫 번째 가사")
        let cache = SongSearchTextCache(maximumEntryCount: 4)

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "첫 번째"),
            searchTextCache: cache
        ))

        song.lyricsText = "바뀐 뒤의 새 가사"

        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "첫 번째"),
            searchTextCache: cache
        ))
        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "새 가사"),
            searchTextCache: cache
        ))
    }

    func testCachedNotesRefreshWhenSourceNotesChange() {
        let song = Song(title: "메모 수정", notes: "오프닝 곡")
        let cache = SongSearchTextCache(maximumEntryCount: 4)

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "오프닝"),
            searchTextCache: cache
        ))

        song.notes = "마지막 파송곡"

        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "오프닝"),
            searchTextCache: cache
        ))
        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(query: "파송곡"),
            searchTextCache: cache
        ))
    }

    func testSearchTextCacheNeverExceedsConfiguredEntryLimit() {
        let cache = SongSearchTextCache(maximumEntryCount: 2)
        let first = Song(title: "첫째", lyricsText: "은혜")
        let second = Song(title: "둘째", lyricsText: "사랑")
        let third = Song(title: "셋째", lyricsText: "소망")
        let query = SongSearchFilter(query: "없는 단서")

        _ = SongSearchMatcher.matches(first, filter: query, searchTextCache: cache)
        _ = SongSearchMatcher.matches(second, filter: query, searchTextCache: cache)
        _ = SongSearchMatcher.matches(third, filter: query, searchTextCache: cache)

        XCTAssertEqual(cache.cachedEntryCount, 2)
        XCTAssertFalse(cache.contains(songID: first.id))
        XCTAssertTrue(cache.contains(songID: second.id))
        XCTAssertTrue(cache.contains(songID: third.id))
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

    func testCombinesQueryAndFavoriteFilters() {
        let matchingSong = Song(title: "은혜 아니면", isFavorite: true)
        let unrelatedSong = Song(title: "주 사랑", isFavorite: true)
        let notFavoriteSong = Song(title: "은혜로다", isFavorite: false)
        let filter = SongSearchFilter(query: "은혜", favoritesOnly: true)

        let matches = SongSearchMatcher.filter(
            [unrelatedSong, matchingSong, notFavoriteSong],
            using: filter
        )

        XCTAssertEqual(matches.map(\.id), [matchingSong.id])
    }
}
