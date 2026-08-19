import Foundation

struct StagedPDF: Identifiable, Equatable, Sendable {
    let id: UUID
    let originalFileName: String
    let stagingFileName: String
    let checksum: String
    let fileSize: Int64
    let pageCount: Int
}

struct StoredPDF: Equatable, Sendable {
    let storedFileName: String
    let checksum: String
    let fileSize: Int64
    let pageCount: Int
}
