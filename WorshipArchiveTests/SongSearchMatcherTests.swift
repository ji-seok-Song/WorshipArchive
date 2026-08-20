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

    func testMatchesPerformanceDateRangeOnly() throws {
        let calendar = utcCalendar
        let song = Song(title: "주 은혜임을")
        addPerformance(
            to: song,
            performedAt: date(2026, 8, 16, 11, 0, calendar: calendar),
            serviceType: "주일 예배"
        )
        let range = try PerformanceDateRange(
            startDate: date(2026, 8, 16, calendar: calendar),
            endDate: date(2026, 8, 16, calendar: calendar),
            calendar: calendar
        )

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(performanceDateRange: range)
        ))

        let otherDayRange = try PerformanceDateRange(
            startDate: date(2026, 8, 17, calendar: calendar),
            endDate: date(2026, 8, 17, calendar: calendar),
            calendar: calendar
        )
        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(performanceDateRange: otherDayRange)
        ))
    }

    func testMatchesNormalizedServiceTypeExactly() {
        let song = Song(title: "내 주 되신 주를 참 사랑하고")
        addPerformance(
            to: song,
            performedAt: Date(),
            serviceType: "청년   예배"
        )

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(serviceType: "  청년\n예배 ")
        ))
        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(serviceType: "청년")
        ))
    }

    func testDateAndServiceTypeMustMatchSamePerformanceRecord() throws {
        let calendar = utcCalendar
        let song = Song(title: "예수 우리 왕이여")
        addPerformance(
            to: song,
            performedAt: date(2026, 8, 16, 9, 0, calendar: calendar),
            serviceType: "주일 예배"
        )
        addPerformance(
            to: song,
            performedAt: date(2026, 8, 23, 14, 0, calendar: calendar),
            serviceType: "청년 예배"
        )
        let sunday = try PerformanceDateRange(
            startDate: date(2026, 8, 16, calendar: calendar),
            endDate: date(2026, 8, 16, calendar: calendar),
            calendar: calendar
        )

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(
                performanceDateRange: sunday,
                serviceType: "주일 예배"
            )
        ))
    }

    func testDateAndServiceTypeRejectConditionsSplitAcrossRecords() throws {
        let calendar = utcCalendar
        let song = Song(title: "예수 우리 왕이여")
        addPerformance(
            to: song,
            performedAt: date(2026, 8, 16, 9, 0, calendar: calendar),
            serviceType: "주일 예배"
        )
        addPerformance(
            to: song,
            performedAt: date(2026, 8, 23, 14, 0, calendar: calendar),
            serviceType: "청년 예배"
        )
        let sunday = try PerformanceDateRange(
            startDate: date(2026, 8, 16, calendar: calendar),
            endDate: date(2026, 8, 16, calendar: calendar),
            calendar: calendar
        )

        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(
                performanceDateRange: sunday,
                serviceType: "청년 예배"
            )
        ))
    }

    func testCombinesPerformanceWithExistingTextAndKeyFilters() throws {
        let calendar = utcCalendar
        let song = try makeSong(
            title: "나는 주를 섬기는 것에 후회가 없습니다",
            musicalKey: .gMajor,
            isFavorite: false
        )
        addPerformance(
            to: song,
            performedAt: date(2026, 8, 16, 13, 0, calendar: calendar),
            serviceType: "청년 예배"
        )
        let range = try PerformanceDateRange(
            startDate: date(2026, 8, 16, calendar: calendar),
            endDate: date(2026, 8, 16, calendar: calendar),
            calendar: calendar
        )

        XCTAssertTrue(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(
                query: "후회가 없습니다",
                musicalKey: .gMajor,
                performanceDateRange: range,
                serviceType: "청년 예배"
            )
        ))
        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(
                query: "후회가 없습니다",
                musicalKey: .eMajor,
                performanceDateRange: range,
                serviceType: "청년 예배"
            )
        ))
        XCTAssertFalse(SongSearchMatcher.matches(
            song,
            filter: SongSearchFilter(
                query: "없는 검색어",
                musicalKey: .gMajor,
                performanceDateRange: range,
                serviceType: "청년 예배"
            )
        ))
    }

    func testPerformanceDateRangeUsesDSTSafeDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let range = try PerformanceDateRange(
            startDate: date(2026, 3, 8, calendar: calendar),
            endDate: date(2026, 3, 8, calendar: calendar),
            calendar: calendar
        )
        let songBeforeBoundary = Song(title: "주의 친절한 팔에 안기세")
        addPerformance(
            to: songBeforeBoundary,
            performedAt: date(2026, 3, 8, 23, 59, calendar: calendar),
            serviceType: "저녁 예배"
        )
        let songAtBoundary = Song(title: "내 진정 사모하는")
        addPerformance(
            to: songAtBoundary,
            performedAt: date(2026, 3, 9, 0, 0, calendar: calendar),
            serviceType: "저녁 예배"
        )

        XCTAssertTrue(SongSearchMatcher.matches(
            songBeforeBoundary,
            filter: SongSearchFilter(performanceDateRange: range)
        ))
        XCTAssertFalse(SongSearchMatcher.matches(
            songAtBoundary,
            filter: SongSearchFilter(performanceDateRange: range)
        ))
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

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func addPerformance(
        to song: Song,
        performedAt: Date,
        serviceType: String
    ) {
        let record = PerformanceRecord(
            performedAt: performedAt,
            serviceType: serviceType,
            song: song
        )
        song.performanceRecords = (song.performanceRecords ?? []) + [record]
    }
}
