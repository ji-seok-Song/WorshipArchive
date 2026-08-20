import Foundation

nonisolated enum SearchQueryDebounce {
    static let defaultDelay: Duration = .milliseconds(250)

    static func waitIfNeeded(
        pendingQuery: String,
        committedQuery: String,
        delay: Duration = defaultDelay
    ) async throws {
        let normalizedPendingQuery = SearchTextNormalizer.normalize(pendingQuery)
        let normalizedCommittedQuery = SearchTextNormalizer.normalize(committedQuery)

        guard
            !normalizedPendingQuery.isEmpty,
            normalizedPendingQuery != normalizedCommittedQuery
        else {
            return
        }

        try await Task.sleep(for: delay)
        try Task.checkCancellation()
    }
}
