import Foundation

nonisolated struct LocalPDFAsset: Codable, Equatable, Hashable, Sendable {
    let documentID: UUID
    let storedFileName: String
    let checksum: String
    let fileSize: Int64
    let pageCount: Int
}

nonisolated struct RemotePDFAsset: Equatable, Sendable {
    let checksum: String
    let fileSize: Int64
    let pageCount: Int
    let revision: String?
}

nonisolated struct DownloadedPDFAsset: Sendable {
    let metadata: RemotePDFAsset
    let temporaryFileURL: URL
}

nonisolated enum PDFAssetUploadResult: Equatable, Sendable {
    case uploaded(RemotePDFAsset)
    case alreadyPresent(RemotePDFAsset)
}

nonisolated enum CloudAccountAvailability: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

nonisolated enum PDFAssetRemoteError: LocalizedError, Equatable, Sendable {
    case accountUnavailable(CloudAccountAvailability)
    case offline
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExceeded
    case integrityConflict
    case malformedRecord
    case transient

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            "iCloud 계정을 사용할 수 없습니다. 이 기기의 악보는 그대로 유지됩니다."
        case .offline:
            "인터넷에 연결되면 악보 동기화를 다시 시도합니다."
        case .notFound:
            "iCloud에서 이 악보 원본을 찾을 수 없습니다."
        case .rateLimited:
            "iCloud 요청이 잠시 제한되었습니다. 잠시 후 다시 시도합니다."
        case .quotaExceeded:
            "iCloud 저장 공간이 부족합니다. 이 기기의 악보는 그대로 유지됩니다."
        case .integrityConflict:
            "iCloud 악보 원본의 무결성을 확인할 수 없습니다."
        case .malformedRecord:
            "iCloud 악보 정보가 올바르지 않습니다."
        case .transient:
            "iCloud 동기화를 완료하지 못했습니다. 다시 시도해 주세요."
        }
    }
}

nonisolated protocol PDFAssetRemote: Sendable {
    func accountAvailability() async -> CloudAccountAvailability
    func upload(
        _ asset: LocalPDFAsset,
        fileURL: URL
    ) async throws -> PDFAssetUploadResult
    func download(checksum: String) async throws -> DownloadedPDFAsset
}

nonisolated protocol PDFAssetLocalCaching: PDFFileStoring {
    func installDownloadedPDF(
        from temporaryURL: URL,
        named storedFileName: String,
        expectedChecksum: String,
        expectedFileSize: Int64,
        expectedPageCount: Int
    ) async throws -> URL
}

nonisolated struct PDFAssetUploadJob: Codable, Equatable, Sendable, Identifiable {
    var id: String { asset.checksum }

    let asset: LocalPDFAsset
    var attemptCount: Int
    var nextAttemptAt: Date
    var lastErrorCode: String?
}

nonisolated struct PDFAssetJournalSnapshot: Equatable, Sendable {
    let pendingJobs: [PDFAssetUploadJob]
    let uploadedChecksums: Set<String>
}

nonisolated protocol PDFAssetSyncJournal: Sendable {
    func enqueueIfNeeded(_ asset: LocalPDFAsset) async throws
    func dueJobs(at date: Date) async throws -> [PDFAssetUploadJob]
    func markUploaded(checksum: String) async throws
    func reschedule(
        checksum: String,
        attemptCount: Int,
        nextAttemptAt: Date,
        errorCode: String
    ) async throws
    func snapshot() async throws -> PDFAssetJournalSnapshot
}

@MainActor
protocol PDFAssetUploadScheduling: AnyObject {
    func enqueueForUpload(_ asset: LocalPDFAsset) async
}
