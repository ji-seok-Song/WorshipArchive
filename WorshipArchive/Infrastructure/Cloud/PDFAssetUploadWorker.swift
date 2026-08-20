import Foundation

nonisolated struct PDFAssetUploadRetryPolicy: Equatable, Sendable {
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval
    let accountUnavailableDelay: TimeInterval
    let quotaExceededDelay: TimeInterval

    init(
        baseDelay: TimeInterval = 60,
        maximumDelay: TimeInterval = 6 * 60 * 60,
        accountUnavailableDelay: TimeInterval = 6 * 60 * 60,
        quotaExceededDelay: TimeInterval = 24 * 60 * 60
    ) {
        self.baseDelay = max(1, baseDelay)
        self.maximumDelay = max(self.baseDelay, maximumDelay)
        self.accountUnavailableDelay = max(self.baseDelay, accountUnavailableDelay)
        self.quotaExceededDelay = max(self.baseDelay, quotaExceededDelay)
    }

    func retryDelay(
        afterAttempt attemptCount: Int,
        error: PDFAssetRemoteError?
    ) -> TimeInterval {
        switch error {
        case .accountUnavailable:
            return accountUnavailableDelay
        case .quotaExceeded:
            return quotaExceededDelay
        case let .rateLimited(retryAfter):
            return max(exponentialDelay(afterAttempt: attemptCount), retryAfter ?? 0)
        case .integrityConflict, .malformedRecord:
            return maximumDelay
        default:
            return exponentialDelay(afterAttempt: attemptCount)
        }
    }

    private func exponentialDelay(afterAttempt attemptCount: Int) -> TimeInterval {
        let exponent = min(max(0, attemptCount - 1), 30)
        return min(maximumDelay, baseDelay * pow(2, Double(exponent)))
    }
}

nonisolated struct PDFAssetUploadRunSummary: Equatable, Sendable {
    var uploadedCount = 0
    var alreadyPresentCount = 0
    var deferredCount = 0
}

actor PDFAssetUploadWorker {
    private let journal: any PDFAssetSyncJournal
    private let localStore: any StoredPDFAccessing
    private let remote: any PDFAssetRemote
    private let retryPolicy: PDFAssetUploadRetryPolicy

    init(
        journal: any PDFAssetSyncJournal,
        localStore: any StoredPDFAccessing,
        remote: any PDFAssetRemote,
        retryPolicy: PDFAssetUploadRetryPolicy = PDFAssetUploadRetryPolicy()
    ) {
        self.journal = journal
        self.localStore = localStore
        self.remote = remote
        self.retryPolicy = retryPolicy
    }

    func enqueue(_ asset: LocalPDFAsset) async throws {
        try await journal.enqueueIfNeeded(asset)
    }

    func enqueueIfLocalFileExists(_ asset: LocalPDFAsset) async throws {
        do {
            _ = try await localStore.storedFileURL(
                named: asset.storedFileName,
                expectedChecksum: asset.checksum
            )
            try await journal.enqueueIfNeeded(asset)
        } catch PDFFileStoreError.storedFileMissing {
            // Metadata received from another device is download-only until the
            // user opens it. Do not create a false upload failure for it.
        }
    }

    func processDueJobs(at date: Date = Date()) async throws -> PDFAssetUploadRunSummary {
        let jobs = try await journal.dueJobs(at: date)
        return try await process(jobs, at: date)
    }

    func processAllPendingJobs(at date: Date = Date()) async throws -> PDFAssetUploadRunSummary {
        let jobs = (try await journal.snapshot()).pendingJobs
        return try await process(jobs, at: date)
    }

    func snapshot() async throws -> PDFAssetJournalSnapshot {
        try await journal.snapshot()
    }

    private func process(
        _ jobs: [PDFAssetUploadJob],
        at date: Date
    ) async throws -> PDFAssetUploadRunSummary {
        guard !jobs.isEmpty else { return PDFAssetUploadRunSummary() }

        let availability = await remote.accountAvailability()
        guard availability == .available else {
            try await deferAll(
                jobs,
                at: date,
                error: .accountUnavailable(availability)
            )
            return PDFAssetUploadRunSummary(deferredCount: jobs.count)
        }

        var summary = PDFAssetUploadRunSummary()
        for (index, job) in jobs.enumerated() {
            try Task.checkCancellation()

            do {
                let fileURL = try await localStore.storedFileURL(
                    named: job.asset.storedFileName,
                    expectedChecksum: job.asset.checksum
                )
                let result = try await remote.upload(job.asset, fileURL: fileURL)
                try validate(result, for: job.asset)
                try await journal.markUploaded(checksum: job.asset.checksum)

                switch result {
                case .uploaded:
                    summary.uploadedCount += 1
                case .alreadyPresent:
                    summary.alreadyPresentCount += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let remoteError = error as? PDFAssetRemoteError
                try await deferJob(job, at: date, error: remoteError, underlyingError: error)
                summary.deferredCount += 1

                if Self.isAccountWidePause(remoteError) {
                    let remainingJobs = Array(jobs.dropFirst(index + 1))
                    try await deferAll(
                        remainingJobs,
                        at: date,
                        error: remoteError ?? .transient
                    )
                    summary.deferredCount += remainingJobs.count
                    break
                }
            }
        }
        return summary
    }

    private func validate(
        _ result: PDFAssetUploadResult,
        for localAsset: LocalPDFAsset
    ) throws {
        let remoteAsset: RemotePDFAsset
        switch result {
        case let .uploaded(asset), let .alreadyPresent(asset):
            remoteAsset = asset
        }

        guard remoteAsset.checksum == localAsset.checksum,
              remoteAsset.fileSize == localAsset.fileSize,
              remoteAsset.pageCount == localAsset.pageCount else {
            throw PDFAssetRemoteError.integrityConflict
        }
    }

    private func deferAll(
        _ jobs: [PDFAssetUploadJob],
        at date: Date,
        error: PDFAssetRemoteError
    ) async throws {
        for job in jobs {
            try await deferJob(job, at: date, error: error, underlyingError: error)
        }
    }

    private func deferJob(
        _ job: PDFAssetUploadJob,
        at date: Date,
        error: PDFAssetRemoteError?,
        underlyingError: Error
    ) async throws {
        let attemptCount = job.attemptCount + 1
        let delay = retryPolicy.retryDelay(
            afterAttempt: attemptCount,
            error: error
        )
        try await journal.reschedule(
            checksum: job.asset.checksum,
            attemptCount: attemptCount,
            nextAttemptAt: date.addingTimeInterval(delay),
            errorCode: Self.errorCode(for: error, underlyingError: underlyingError)
        )
    }

    private static func isAccountWidePause(_ error: PDFAssetRemoteError?) -> Bool {
        switch error {
        case .accountUnavailable, .quotaExceeded:
            return true
        default:
            return false
        }
    }

    private static func errorCode(
        for error: PDFAssetRemoteError?,
        underlyingError: Error
    ) -> String {
        switch error {
        case let .accountUnavailable(availability):
            return "accountUnavailable.\(availability)"
        case .offline:
            return "offline"
        case .notFound:
            return "notFound"
        case .rateLimited:
            return "rateLimited"
        case .quotaExceeded:
            return "quotaExceeded"
        case .integrityConflict:
            return "integrityConflict"
        case .malformedRecord:
            return "malformedRecord"
        case .transient:
            return "transient"
        case nil:
            return String(reflecting: type(of: underlyingError))
        }
    }
}
