import Foundation
import XCTest
@testable import WorshipArchive

final class PDFAssetUploadWorkerTests: XCTestCase {
    func testJournalReopensWithPendingJobsAndUploadedChecksums() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let pendingAsset = makeAsset(checksum: "pending")
        let uploadedAsset = makeAsset(checksum: "uploaded")

        let firstJournal = FilePDFAssetSyncJournal(fileURL: fixture.fileURL, now: { now })
        try await firstJournal.enqueueIfNeeded(pendingAsset)
        try await firstJournal.enqueueIfNeeded(uploadedAsset)
        try await firstJournal.markUploaded(checksum: uploadedAsset.checksum)
        try await firstJournal.enqueueIfNeeded(uploadedAsset)

        let reopenedJournal = FilePDFAssetSyncJournal(fileURL: fixture.fileURL)
        let snapshot = try await reopenedJournal.snapshot()

        XCTAssertEqual(snapshot.pendingJobs.map(\.asset.checksum), ["pending"])
        XCTAssertEqual(snapshot.uploadedChecksums, ["uploaded"])
    }

    func testEnqueueIsIdempotentByChecksumAndDueJobsAreDeterministic() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_000)
        let journal = FilePDFAssetSyncJournal(fileURL: fixture.fileURL, now: { now })

        try await journal.enqueueIfNeeded(makeAsset(checksum: "c"))
        try await journal.enqueueIfNeeded(makeAsset(checksum: "a"))
        try await journal.enqueueIfNeeded(makeAsset(checksum: "b"))
        try await journal.enqueueIfNeeded(
            makeAsset(checksum: "a", documentID: UUID(), storedFileName: "replacement.pdf")
        )

        let dueJobs = try await journal.dueJobs(at: now)
        XCTAssertEqual(dueJobs.map(\.asset.checksum), ["a", "b", "c"])
        XCTAssertEqual(dueJobs.count, 3)
        XCTAssertNotEqual(dueJobs[0].asset.storedFileName, "replacement.pdf")
    }

    func testSuccessfulAndAlreadyPresentUploadsArePersistentlyMarkedUploaded() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 3_000)
        let uploadedAsset = makeAsset(checksum: "a-uploaded")
        let existingAsset = makeAsset(checksum: "b-existing")
        let local = FakeStoredPDFAccessor(entries: [
            uploadedAsset: fixture.pdfURL,
            existingAsset: fixture.pdfURL
        ])
        let remote = FakePDFAssetRemote(outcomes: [
            uploadedAsset.checksum: [.success(.uploaded(remoteAsset(for: uploadedAsset)))],
            existingAsset.checksum: [.success(.alreadyPresent(remoteAsset(for: existingAsset)))]
        ])
        let journal = FilePDFAssetSyncJournal(fileURL: fixture.fileURL, now: { now })
        let worker = PDFAssetUploadWorker(journal: journal, localStore: local, remote: remote)

        try await worker.enqueue(existingAsset)
        try await worker.enqueue(uploadedAsset)
        let summary = try await worker.processDueJobs(at: now)

        XCTAssertEqual(summary.uploadedCount, 1)
        XCTAssertEqual(summary.alreadyPresentCount, 1)
        XCTAssertEqual(summary.deferredCount, 0)
        let reopenedSnapshot = try await FilePDFAssetSyncJournal(fileURL: fixture.fileURL).snapshot()
        XCTAssertTrue(reopenedSnapshot.pendingJobs.isEmpty)
        XCTAssertEqual(
            reopenedSnapshot.uploadedChecksums,
            [uploadedAsset.checksum, existingAsset.checksum]
        )
        let requestedChecksums = await local.requestedChecksums()
        XCTAssertEqual(requestedChecksums, [uploadedAsset.checksum, existingAsset.checksum])
    }

    func testTransientFailuresRemainPendingWithExponentialBackoff() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 4_000)
        let asset = makeAsset(checksum: "retry")
        let local = FakeStoredPDFAccessor(entries: [asset: fixture.pdfURL])
        let remote = FakePDFAssetRemote(outcomes: [
            asset.checksum: [.failure(.offline), .failure(.transient)]
        ])
        let journal = FilePDFAssetSyncJournal(fileURL: fixture.fileURL, now: { now })
        let worker = PDFAssetUploadWorker(
            journal: journal,
            localStore: local,
            remote: remote,
            retryPolicy: PDFAssetUploadRetryPolicy(
                baseDelay: 10,
                maximumDelay: 100,
                accountUnavailableDelay: 300,
                quotaExceededDelay: 600
            )
        )
        try await worker.enqueue(asset)

        let firstSummary = try await worker.processDueJobs(at: now)
        XCTAssertEqual(firstSummary.deferredCount, 1)
        var snapshot = try await journal.snapshot()
        var job = try XCTUnwrap(snapshot.pendingJobs.first)
        XCTAssertEqual(job.attemptCount, 1)
        XCTAssertEqual(job.nextAttemptAt, now.addingTimeInterval(10))
        XCTAssertEqual(job.lastErrorCode, "offline")

        let earlySummary = try await worker.processDueJobs(at: now.addingTimeInterval(9))
        XCTAssertEqual(earlySummary, PDFAssetUploadRunSummary())
        let uploadCountBeforeRetry = await remote.uploadCount()
        XCTAssertEqual(uploadCountBeforeRetry, 1)

        let retryDate = now.addingTimeInterval(10)
        let secondSummary = try await worker.processDueJobs(at: retryDate)
        XCTAssertEqual(secondSummary.deferredCount, 1)
        snapshot = try await journal.snapshot()
        job = try XCTUnwrap(snapshot.pendingJobs.first)
        XCTAssertEqual(job.attemptCount, 2)
        XCTAssertEqual(job.nextAttemptAt, retryDate.addingTimeInterval(20))
        XCTAssertEqual(job.lastErrorCode, "transient")
    }

    func testUnavailableAccountDefersWithoutReadingOrUploadingFiles() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 5_000)
        let firstAsset = makeAsset(checksum: "a")
        let secondAsset = makeAsset(checksum: "b")
        let local = FakeStoredPDFAccessor(entries: [
            firstAsset: fixture.pdfURL,
            secondAsset: fixture.pdfURL
        ])
        let remote = FakePDFAssetRemote(availability: .noAccount)
        let journal = FilePDFAssetSyncJournal(fileURL: fixture.fileURL, now: { now })
        let worker = PDFAssetUploadWorker(
            journal: journal,
            localStore: local,
            remote: remote,
            retryPolicy: PDFAssetUploadRetryPolicy(accountUnavailableDelay: 300)
        )
        try await worker.enqueue(firstAsset)
        try await worker.enqueue(secondAsset)

        let summary = try await worker.processDueJobs(at: now)

        XCTAssertEqual(summary.deferredCount, 2)
        let uploadCount = await remote.uploadCount()
        let requestedChecksums = await local.requestedChecksums()
        let snapshot = try await journal.snapshot()
        let jobs = snapshot.pendingJobs
        XCTAssertEqual(uploadCount, 0)
        XCTAssertTrue(requestedChecksums.isEmpty)
        XCTAssertEqual(jobs.map(\.nextAttemptAt), Array(repeating: now.addingTimeInterval(300), count: 2))
        XCTAssertTrue(jobs.allSatisfy { $0.lastErrorCode == "accountUnavailable.noAccount" })
    }

    func testQuotaFailurePausesRemainingJobsInsteadOfBusyRetrying() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 6_000)
        let firstAsset = makeAsset(checksum: "a")
        let secondAsset = makeAsset(checksum: "b")
        let local = FakeStoredPDFAccessor(entries: [
            firstAsset: fixture.pdfURL,
            secondAsset: fixture.pdfURL
        ])
        let remote = FakePDFAssetRemote(outcomes: [
            firstAsset.checksum: [.failure(.quotaExceeded)]
        ])
        let journal = FilePDFAssetSyncJournal(fileURL: fixture.fileURL, now: { now })
        let worker = PDFAssetUploadWorker(
            journal: journal,
            localStore: local,
            remote: remote,
            retryPolicy: PDFAssetUploadRetryPolicy(quotaExceededDelay: 600)
        )
        try await worker.enqueue(secondAsset)
        try await worker.enqueue(firstAsset)

        let summary = try await worker.processDueJobs(at: now)

        XCTAssertEqual(summary.deferredCount, 2)
        let uploadCount = await remote.uploadCount()
        let requestedChecksums = await local.requestedChecksums()
        let snapshot = try await journal.snapshot()
        let jobs = snapshot.pendingJobs
        XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(requestedChecksums, [firstAsset.checksum])
        XCTAssertEqual(jobs.map(\.nextAttemptAt), Array(repeating: now.addingTimeInterval(600), count: 2))
        XCTAssertTrue(jobs.allSatisfy { $0.lastErrorCode == "quotaExceeded" })
    }

    func testCloudFailureNeverRemovesTheLocalPDF() async throws {
        let fixture = try JournalFixture(pdfData: Data("original-pdf-data".utf8))
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 7_000)
        let asset = makeAsset(checksum: "preserved")
        let local = FakeStoredPDFAccessor(entries: [asset: fixture.pdfURL])
        let remote = FakePDFAssetRemote(outcomes: [
            asset.checksum: [.failure(.transient)]
        ])
        let journal = FilePDFAssetSyncJournal(fileURL: fixture.fileURL, now: { now })
        let worker = PDFAssetUploadWorker(journal: journal, localStore: local, remote: remote)
        try await worker.enqueue(asset)

        _ = try await worker.processDueJobs(at: now)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.pdfURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.pdfURL), Data("original-pdf-data".utf8))
        let snapshot = try await journal.snapshot()
        XCTAssertEqual(snapshot.pendingJobs.map(\.asset.checksum), ["preserved"])
    }
}

private struct JournalFixture {
    let directoryURL: URL
    let fileURL: URL
    let pdfURL: URL

    init(pdfData: Data = Data("pdf".utf8)) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "PDFAssetUploadWorkerTests-\(UUID().uuidString)")
        fileURL = directoryURL.appending(path: "PDFAssetSyncJournal.json")
        pdfURL = directoryURL.appending(path: "stored.pdf")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try pdfData.write(to: pdfURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private actor FakeStoredPDFAccessor: StoredPDFAccessing {
    private struct Entry: Sendable {
        let checksum: String
        let fileURL: URL
    }

    private let entriesByFileName: [String: Entry]
    private var checksums: [String] = []

    init(entries: [LocalPDFAsset: URL]) {
        entriesByFileName = Dictionary(
            uniqueKeysWithValues: entries.map {
                ($0.key.storedFileName, Entry(checksum: $0.key.checksum, fileURL: $0.value))
            }
        )
    }

    func storedFileURL(
        named storedFileName: String,
        expectedChecksum: String
    ) throws -> URL {
        checksums.append(expectedChecksum)
        guard let entry = entriesByFileName[storedFileName] else {
            throw PDFFileStoreError.storedFileMissing
        }
        guard entry.checksum == expectedChecksum else {
            throw PDFFileStoreError.storedFileChanged
        }
        return entry.fileURL
    }

    func requestedChecksums() -> [String] {
        checksums
    }
}

private actor FakePDFAssetRemote: PDFAssetRemote {
    private var availability: CloudAccountAvailability
    private var outcomes: [String: [Result<PDFAssetUploadResult, PDFAssetRemoteError>]]
    private var uploadedChecksums: [String] = []

    init(
        availability: CloudAccountAvailability = .available,
        outcomes: [String: [Result<PDFAssetUploadResult, PDFAssetRemoteError>]] = [:]
    ) {
        self.availability = availability
        self.outcomes = outcomes
    }

    func accountAvailability() -> CloudAccountAvailability {
        availability
    }

    func upload(
        _ asset: LocalPDFAsset,
        fileURL: URL
    ) throws -> PDFAssetUploadResult {
        uploadedChecksums.append(asset.checksum)
        guard var assetOutcomes = outcomes[asset.checksum], !assetOutcomes.isEmpty else {
            return .uploaded(remoteAsset(for: asset))
        }
        let outcome = assetOutcomes.removeFirst()
        outcomes[asset.checksum] = assetOutcomes
        return try outcome.get()
    }

    func download(checksum: String) throws -> DownloadedPDFAsset {
        throw PDFAssetRemoteError.notFound
    }

    func uploadCount() -> Int {
        uploadedChecksums.count
    }
}

nonisolated private func makeAsset(
    checksum: String,
    documentID: UUID = UUID(),
    storedFileName: String? = nil
) -> LocalPDFAsset {
    LocalPDFAsset(
        documentID: documentID,
        storedFileName: storedFileName ?? "\(documentID.uuidString.lowercased()).pdf",
        checksum: checksum,
        fileSize: 3,
        pageCount: 1
    )
}

nonisolated private func remoteAsset(for localAsset: LocalPDFAsset) -> RemotePDFAsset {
    RemotePDFAsset(
        checksum: localAsset.checksum,
        fileSize: localAsset.fileSize,
        pageCount: localAsset.pageCount,
        revision: nil
    )
}
