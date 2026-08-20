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

    func testCombinesQueryKeyAndFavoriteFilters() throws {
        let matchingSong = try makeSong(
            title: "은혜 아니면",
            musicalKey: .gMajor,
            isFavorite: true
        )
        let wrongKeySong = try makeSong(
            title: "은혜로다",
            musicalKey: .eMajor,
            isFavorite: true
        )
        let notFavoriteSong = try makeSong(
            title: "은혜",
            musicalKey: .gMajor,
            isFavorite: false
        )
        let filter = SongSearchFilter(
            query: "은혜",
            musicalKey: .gMajor,
            favoritesOnly: true
        )

        let matches = SongSearchMatcher.filter(
            [wrongKeySong, matchingSong, notFavoriteSong],
            using: filter
        )

        XCTAssertEqual(matches.map(\.id), [matchingSong.id])
    }

    private func makeSong(
        title: String,
        musicalKey: MusicalKey,
        isFavorite: Bool
    ) throws -> Song {
        let document = ArchiveDocument(
            originalFileName: "\(title).pdf",
            storedFileName: "\(UUID().uuidString).pdf",
            pageCount: 1,
            fileSize: 1,
            checksum: UUID().uuidString,
            analysisStatus: .completed
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
        return song
    }
}
