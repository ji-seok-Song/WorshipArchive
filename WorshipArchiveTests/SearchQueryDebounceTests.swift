import XCTest
@testable import WorshipArchive

final class SearchQueryDebounceTests: XCTestCase {
    func testEmptyQueryBypassesDelay() async throws {
        try await SearchQueryDebounce.waitIfNeeded(
            pendingQuery: "  \n ",
            committedQuery: "은혜",
            delay: .seconds(30)
        )
    }

    func testEquivalentNormalizedQueryBypassesDelay() async throws {
        try await SearchQueryDebounce.waitIfNeeded(
            pendingQuery: "  주   사랑\n",
            committedQuery: "주 사랑",
            delay: .seconds(30)
        )
    }

    func testCancellationStopsPendingDebounce() async {
        let task = Task {
            try await SearchQueryDebounce.waitIfNeeded(
                pendingQuery: "새 검색어",
                committedQuery: "기존 검색어",
                delay: .seconds(30)
            )
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("취소된 검색어가 반영되면 안 됩니다.")
        } catch is CancellationError {
            // Expected cancellation keeps the previously committed query intact.
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
    }
}
