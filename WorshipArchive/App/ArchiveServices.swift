import Foundation

@MainActor
final class ArchiveServices {
    static let live = ArchiveServices()

    let fileStore: CloudBackedPDFFileStore
    let syncCoordinator: ArchiveSyncCoordinator

    private init() {
        let localFileStore = LocalPDFFileStore.live()
        let remote = CloudKitPDFAssetStore.live(
            containerIdentifier: AppModelContainer.cloudKitContainerIdentifier
        )
        let journal = FilePDFAssetSyncJournal.live()
        let worker = PDFAssetUploadWorker(
            journal: journal,
            localStore: localFileStore,
            remote: remote
        )

        fileStore = CloudBackedPDFFileStore(
            localFileStore: localFileStore,
            remote: remote
        )
        syncCoordinator = ArchiveSyncCoordinator(
            worker: worker,
            remote: remote
        )
    }
}
