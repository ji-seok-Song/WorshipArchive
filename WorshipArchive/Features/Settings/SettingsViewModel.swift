import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    @ObservationIgnored
    private let syncCoordinator: ArchiveSyncCoordinator?

    let appVersion: String

    init(
        syncCoordinator: ArchiveSyncCoordinator?,
        appVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    ) {
        self.syncCoordinator = syncCoordinator
        self.appVersion = appVersion
    }

    var syncStatus: ArchiveSyncCoordinator.Status? {
        syncCoordinator?.status
    }

    func retrySync() {
        syncCoordinator?.retry()
    }

    func localOnlyText(_ reason: CloudAccountAvailability) -> String {
        switch reason {
        case .noAccount:
            "iCloud 로그인 필요"
        case .restricted:
            "계정에서 사용 제한됨"
        case .temporarilyUnavailable, .couldNotDetermine:
            "일시적으로 사용할 수 없음"
        case .available:
            "사용 중"
        }
    }

    func canRetry(_ status: ArchiveSyncCoordinator.Status) -> Bool {
        switch status {
        case .localOnly, .offline, .failed:
            true
        case .checking, .syncing, .active:
            false
        }
    }

    func isSyncing(_ status: ArchiveSyncCoordinator.Status) -> Bool {
        if case .syncing = status { return true }
        return false
    }
}
