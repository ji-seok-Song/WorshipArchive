import Foundation

actor FilePDFAssetSyncJournal: PDFAssetSyncJournal {
    nonisolated private struct PersistedState: Codable {
        static let currentVersion = 1

        var version = currentVersion
        var pendingJobsByChecksum: [String: PDFAssetUploadJob] = [:]
        var uploadedChecksums: Set<String> = []
    }

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var loadedState: PersistedState?

    init(
        fileURL: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.now = now
    }

    static func live() -> FilePDFAssetSyncJournal {
        let fileURL = URL.applicationSupportDirectory
            .appending(path: "WorshipArchive", directoryHint: .isDirectory)
            .appending(path: "Cloud", directoryHint: .isDirectory)
            .appending(path: "PDFAssetSyncJournal.json")
        return FilePDFAssetSyncJournal(fileURL: fileURL)
    }

    func enqueueIfNeeded(_ asset: LocalPDFAsset) throws {
        let state = try state()
        guard !state.uploadedChecksums.contains(asset.checksum) else { return }
        guard state.pendingJobsByChecksum[asset.checksum] == nil else { return }

        var candidate = state
        candidate.pendingJobsByChecksum[asset.checksum] = PDFAssetUploadJob(
            asset: asset,
            attemptCount: 0,
            nextAttemptAt: now(),
            lastErrorCode: nil
        )
        try persistAndAdopt(candidate)
    }

    func dueJobs(at date: Date) throws -> [PDFAssetUploadJob] {
        try state().pendingJobsByChecksum.values
            .filter { $0.nextAttemptAt <= date }
            .sorted(by: Self.jobSortOrder)
    }

    func markUploaded(checksum: String) throws {
        let state = try state()
        guard state.pendingJobsByChecksum[checksum] != nil
                || !state.uploadedChecksums.contains(checksum) else {
            return
        }

        var candidate = state
        candidate.pendingJobsByChecksum.removeValue(forKey: checksum)
        candidate.uploadedChecksums.insert(checksum)
        try persistAndAdopt(candidate)
    }

    func reschedule(
        checksum: String,
        attemptCount: Int,
        nextAttemptAt: Date,
        errorCode: String
    ) throws {
        let state = try state()
        guard var job = state.pendingJobsByChecksum[checksum] else { return }
        guard !state.uploadedChecksums.contains(checksum) else { return }

        job.attemptCount = attemptCount
        job.nextAttemptAt = nextAttemptAt
        job.lastErrorCode = errorCode

        var candidate = state
        candidate.pendingJobsByChecksum[checksum] = job
        try persistAndAdopt(candidate)
    }

    func snapshot() throws -> PDFAssetJournalSnapshot {
        let state = try state()
        return PDFAssetJournalSnapshot(
            pendingJobs: state.pendingJobsByChecksum.values.sorted(by: Self.jobSortOrder),
            uploadedChecksums: state.uploadedChecksums
        )
    }

    private func state() throws -> PersistedState {
        if let loadedState {
            return loadedState
        }

        let state: PersistedState
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            state = try decoder.decode(PersistedState.self, from: data)
        } else {
            state = PersistedState()
        }
        loadedState = state
        return state
    }

    private func persistAndAdopt(_ candidate: PersistedState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(candidate)
        try data.write(to: fileURL, options: .atomic)
        loadedState = candidate
    }

    private static func jobSortOrder(
        _ lhs: PDFAssetUploadJob,
        _ rhs: PDFAssetUploadJob
    ) -> Bool {
        if lhs.nextAttemptAt != rhs.nextAttemptAt {
            return lhs.nextAttemptAt < rhs.nextAttemptAt
        }
        return lhs.asset.checksum < rhs.asset.checksum
    }
}
