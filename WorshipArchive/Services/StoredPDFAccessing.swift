import Foundation

nonisolated protocol StoredPDFAccessing: Sendable {
    func storedFileURL(
        named storedFileName: String,
        expectedChecksum: String
    ) async throws -> URL
}
