import Foundation

actor CloudBackedPDFFileStore: PDFAssetLocalCaching {
    private struct ActiveDownload {
        let id: UUID
        let task: Task<URL, Error>
    }

    private let localFileStore: any PDFAssetLocalCaching
    private let remote: any PDFAssetRemote
    private var activeDownloadsByChecksum: [String: ActiveDownload] = [:]

    init(
        localFileStore: any PDFAssetLocalCaching,
        remote: any PDFAssetRemote
    ) {
        self.localFileStore = localFileStore
        self.remote = remote
    }

    func stagePDF(from sourceURL: URL) async throws -> StagedPDF {
        try await localFileStore.stagePDF(from: sourceURL)
    }

    func stagedFileURL(for stagedPDF: StagedPDF) async throws -> URL {
        try await localFileStore.stagedFileURL(for: stagedPDF)
    }

    func commit(_ stagedPDF: StagedPDF) async throws -> StoredPDF {
        try await localFileStore.commit(stagedPDF)
    }

    func discard(_ stagedPDF: StagedPDF) async {
        await localFileStore.discard(stagedPDF)
    }

    func removeStoredFile(named storedFileName: String) async throws {
        try await localFileStore.removeStoredFile(named: storedFileName)
    }

    func removeStaleStagedFiles(olderThan cutoffDate: Date) async throws {
        try await localFileStore.removeStaleStagedFiles(olderThan: cutoffDate)
    }

    func removeUnreferencedStoredFiles(
        keeping referencedFileNames: Set<String>,
        olderThan cutoffDate: Date
    ) async throws {
        try await localFileStore.removeUnreferencedStoredFiles(
            keeping: referencedFileNames,
            olderThan: cutoffDate
        )
    }

    func installDownloadedPDF(
        from temporaryURL: URL,
        named storedFileName: String,
        expectedChecksum: String,
        expectedFileSize: Int64,
        expectedPageCount: Int
    ) async throws -> URL {
        try await localFileStore.installDownloadedPDF(
            from: temporaryURL,
            named: storedFileName,
            expectedChecksum: expectedChecksum,
            expectedFileSize: expectedFileSize,
            expectedPageCount: expectedPageCount
        )
    }

    func storedFileURL(
        named storedFileName: String,
        expectedChecksum: String
    ) async throws -> URL {
        do {
            return try await localFileStore.storedFileURL(
                named: storedFileName,
                expectedChecksum: expectedChecksum
            )
        } catch let error as PDFFileStoreError where error == .storedFileMissing {
            // Only an absent local file may fall back to the network. A corrupt or
            // unsafe local path must remain visible instead of being overwritten.
        }

        let activeDownload: ActiveDownload
        if let existingDownload = activeDownloadsByChecksum[expectedChecksum] {
            activeDownload = existingDownload
        } else {
            let downloadID = UUID()
            let localFileStore = self.localFileStore
            let remote = self.remote
            let task = Task<URL, Error> {
                try Task.checkCancellation()
                let downloadedPDF = try await remote.download(
                    checksum: expectedChecksum
                )
                defer {
                    try? FileManager.default.removeItem(
                        at: downloadedPDF.temporaryFileURL
                    )
                }
                try Task.checkCancellation()

                let metadata = downloadedPDF.metadata
                guard
                    metadata.checksum == expectedChecksum,
                    metadata.fileSize >= 0,
                    metadata.pageCount > 0
                else {
                    throw PDFAssetRemoteError.integrityConflict
                }

                return try await localFileStore.installDownloadedPDF(
                    from: downloadedPDF.temporaryFileURL,
                    named: storedFileName,
                    expectedChecksum: metadata.checksum,
                    expectedFileSize: metadata.fileSize,
                    expectedPageCount: metadata.pageCount
                )
            }
            activeDownload = ActiveDownload(id: downloadID, task: task)
            activeDownloadsByChecksum[expectedChecksum] = activeDownload
        }

        do {
            let fileURL = try await activeDownload.task.value
            removeActiveDownload(
                checksum: expectedChecksum,
                id: activeDownload.id
            )
            try Task.checkCancellation()
            return fileURL
        } catch {
            removeActiveDownload(
                checksum: expectedChecksum,
                id: activeDownload.id
            )
            throw error
        }
    }

    private func removeActiveDownload(checksum: String, id: UUID) {
        guard activeDownloadsByChecksum[checksum]?.id == id else { return }
        activeDownloadsByChecksum.removeValue(forKey: checksum)
    }
}
