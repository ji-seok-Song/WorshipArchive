import Foundation
import Observation

@MainActor
@Observable
final class ArchiveSyncCoordinator: PDFAssetUploadScheduling {
    enum Status: Equatable {
        case checking
        case syncing(pendingCount: Int)
        case active(pendingCount: Int, lastSuccess: Date?)
        case localOnly(CloudAccountAvailability, pendingCount: Int)
        case offline(pendingCount: Int)
        case failed(message: String, pendingCount: Int)
    }

    private(set) var status: Status = .checking

    @ObservationIgnored
    private let worker: PDFAssetUploadWorker
    @ObservationIgnored
    private let remote: any PDFAssetRemote
    @ObservationIgnored
    private var isSynchronizing = false
    @ObservationIgnored
    private var needsAnotherRun = false
    @ObservationIgnored
    private var forceNextRun = false
    @ObservationIgnored
    private var lastSuccess: Date?

    init(worker: PDFAssetUploadWorker, remote: any PDFAssetRemote) {
        self.worker = worker
        self.remote = remote
    }

    func reconcile(_ assets: [LocalPDFAsset]) async {
        do {
            for asset in assets {
                try await worker.enqueueIfLocalFileExists(asset)
            }
        } catch {
            status = .failed(message: error.localizedDescription, pendingCount: pendingCount)
            return
        }

        await synchronize()
    }

    func enqueueForUpload(_ asset: LocalPDFAsset) async {
        do {
            try await worker.enqueue(asset)
            let snapshot = try await worker.snapshot()
            status = .syncing(pendingCount: snapshot.pendingJobs.count)
        } catch {
            status = .failed(message: error.localizedDescription, pendingCount: pendingCount)
            return
        }

        Task { [weak self] in
            await self?.synchronize()
        }
    }

    func retry() {
        Task { [weak self] in
            await self?.synchronize(force: true)
        }
    }

    private func synchronize(force: Bool = false) async {
        if isSynchronizing {
            needsAnotherRun = true
            forceNextRun = forceNextRun || force
            return
        }

        isSynchronizing = true
        var shouldForce = force
        repeat {
            needsAnotherRun = false
            forceNextRun = false
            await performSynchronization(force: shouldForce)
            shouldForce = forceNextRun
        } while needsAnotherRun
        isSynchronizing = false
    }

    private func performSynchronization(force: Bool) async {
        do {
            let before = try await worker.snapshot()
            status = .syncing(pendingCount: before.pendingJobs.count)

            let availability = await remote.accountAvailability()
            guard availability == .available else {
                status = .localOnly(availability, pendingCount: before.pendingJobs.count)
                return
            }

            let result = force
                ? try await worker.processAllPendingJobs()
                : try await worker.processDueJobs()
            if result.uploadedCount + result.alreadyPresentCount > 0 {
                lastSuccess = Date()
            }

            let after = try await worker.snapshot()
            let pendingCount = after.pendingJobs.count
            if pendingCount == 0 {
                status = .active(pendingCount: 0, lastSuccess: lastSuccess)
            } else if after.pendingJobs.contains(where: { $0.lastErrorCode == "offline" }) {
                status = .offline(pendingCount: pendingCount)
            } else {
                let message = after.pendingJobs.first?.lastErrorCode
                    .map(Self.message(for:))
                    ?? "일부 악보가 iCloud 동기화를 기다리고 있습니다."
                status = .failed(message: message, pendingCount: pendingCount)
            }
        } catch is CancellationError {
            // A later reconciliation will refresh the visible state.
        } catch {
            status = .failed(message: error.localizedDescription, pendingCount: pendingCount)
        }
    }

    private var pendingCount: Int {
        switch status {
        case .checking:
            0
        case let .syncing(count), let .active(count, _),
             let .localOnly(_, count), let .offline(count),
             let .failed(_, count):
            count
        }
    }

    private static func message(for errorCode: String) -> String {
        if errorCode.hasPrefix("quotaExceeded") {
            return "iCloud 저장 공간이 부족합니다."
        }
        if errorCode.hasPrefix("integrityConflict") || errorCode.hasPrefix("malformedRecord") {
            return "iCloud의 악보 원본을 안전하게 확인하지 못했습니다."
        }
        if errorCode.hasPrefix("accountUnavailable") {
            return "iCloud 계정을 사용할 수 없습니다."
        }
        return "일부 악보가 iCloud 동기화를 기다리고 있습니다."
    }
}
