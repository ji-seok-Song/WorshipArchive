import SwiftUI
import SwiftData

private actor ArchiveFileMaintenanceGate {
    static let shared = ArchiveFileMaintenanceGate()

    private var hasStarted = false

    func beginIfNeeded() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }
}

struct ContentView: View {
    @Query(sort: \ArchiveDocument.importedAt) private var documents: [ArchiveDocument]

    @State private var selection: AppDestination = .home
    @State private var isPDFImportPresented = false
    @State private var didPerformFileMaintenance = false

    private let fileStore: any PDFFileStoring
    private let pdfAnalyzer: any PDFAnalyzing
    private let syncCoordinator: ArchiveSyncCoordinator?
    private let performsFileMaintenance: Bool

    init(
        fileStore: any PDFFileStoring = LocalPDFFileStore.live(),
        pdfAnalyzer: any PDFAnalyzing = LocalPDFAnalyzer(),
        syncCoordinator: ArchiveSyncCoordinator? = nil,
        performsFileMaintenance: Bool = true
    ) {
        self.fileStore = fileStore
        self.pdfAnalyzer = pdfAnalyzer
        self.syncCoordinator = syncCoordinator
        self.performsFileMaintenance = performsFileMaintenance
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(
                    fileAccess: fileStore,
                    navigate: { destination in
                        selection = destination
                    },
                    addPDF: {
                        isPDFImportPresented = true
                    }
                )
            }
            .tabItem {
                Label(AppDestination.home.title, systemImage: AppDestination.home.systemImage)
            }
            .tag(AppDestination.home)

            NavigationStack {
                SearchView(fileAccess: fileStore) {
                    isPDFImportPresented = true
                }
            }
            .tabItem {
                Label(AppDestination.search.title, systemImage: AppDestination.search.systemImage)
            }
            .tag(AppDestination.search)

            NavigationStack {
                LibraryView(fileAccess: fileStore) {
                    isPDFImportPresented = true
                }
            }
            .tabItem {
                Label(AppDestination.library.title, systemImage: AppDestination.library.systemImage)
            }
            .tag(AppDestination.library)

            NavigationStack {
                SettingsView(syncCoordinator: syncCoordinator)
            }
            .tabItem {
                Label(AppDestination.settings.title, systemImage: AppDestination.settings.systemImage)
            }
            .tag(AppDestination.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(isPresented: $isPDFImportPresented) {
            PDFImportView(
                fileStore: fileStore,
                pdfAnalyzer: pdfAnalyzer,
                uploadScheduler: syncCoordinator
            )
        }
        .task {
            await performFileMaintenanceIfNeeded()
        }
        .task(id: syncAssets) {
            await syncCoordinator?.reconcile(syncAssets)
        }
    }

    private var syncAssets: [LocalPDFAsset] {
        documents.compactMap { document in
            guard
                !document.storedFileName.isEmpty,
                !document.checksum.isEmpty,
                document.fileSize >= 0,
                document.pageCount > 0
            else {
                return nil
            }
            return LocalPDFAsset(
                documentID: document.id,
                storedFileName: document.storedFileName,
                checksum: document.checksum,
                fileSize: document.fileSize,
                pageCount: document.pageCount
            )
        }
    }

    private func performFileMaintenanceIfNeeded() async {
        guard performsFileMaintenance, !didPerformFileMaintenance else { return }
        didPerformFileMaintenance = true
        guard await ArchiveFileMaintenanceGate.shared.beginIfNeeded() else { return }

        let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60)
        try? await fileStore.removeStaleStagedFiles(olderThan: cutoffDate)

        // CloudKit metadata may arrive after launch. Until that first import is
        // complete, an apparently unreferenced PDF can still be valid cloud data.
        guard syncCoordinator == nil else { return }

        let referencedFileNames = Set(documents.map(\.storedFileName))
        try? await fileStore.removeUnreferencedStoredFiles(
            keeping: referencedFileNames,
            olderThan: cutoffDate
        )
    }
}

#Preview {
    ContentView(performsFileMaintenance: false)
        .modelContainer(AppModelContainer.preview)
}
