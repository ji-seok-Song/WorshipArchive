import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct PDFImportRequest: Identifiable {
    let id = UUID()
    let sourceURL: URL?

    static let manual = PDFImportRequest(sourceURL: nil)
}

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
    @State private var pdfImportRequest: PDFImportRequest?
    @State private var incomingDocumentErrorMessage: String?
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
                        presentPDFPicker()
                    }
                )
            }
            .tabItem {
                Label(AppDestination.home.title, systemImage: AppDestination.home.systemImage)
            }
            .tag(AppDestination.home)

            NavigationStack {
                LibraryView(fileAccess: fileStore) {
                    presentPDFPicker()
                }
            }
            .tabItem {
                Label(AppDestination.library.title, systemImage: AppDestination.library.systemImage)
            }
            .tag(AppDestination.library)
            
            NavigationStack {
                SearchView(fileAccess: fileStore) {
                    presentPDFPicker()
                }
            }
            .tabItem {
                Label(AppDestination.search.title, systemImage: AppDestination.search.systemImage)
            }
            .tag(AppDestination.search)

            NavigationStack {
                SettingsView(syncCoordinator: syncCoordinator)
            }
            .tabItem {
                Label(AppDestination.settings.title, systemImage: AppDestination.settings.systemImage)
            }
            .tag(AppDestination.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(item: $pdfImportRequest) { request in
            PDFImportView(
                fileStore: fileStore,
                pdfAnalyzer: pdfAnalyzer,
                uploadScheduler: syncCoordinator,
                initialPDFURL: request.sourceURL
            )
        }
        .onOpenURL(perform: handleIncomingDocument)
        .alert(
            "PDF를 열 수 없어요",
            isPresented: Binding(
                get: { incomingDocumentErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        incomingDocumentErrorMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                incomingDocumentErrorMessage = nil
            }
        } message: {
            Text(incomingDocumentErrorMessage ?? "PDF 파일인지 확인해 주세요.")
        }
        .task {
            await performFileMaintenanceIfNeeded()
        }
        .task(id: syncAssets) {
            await syncCoordinator?.reconcile(syncAssets)
        }
    }

    private func presentPDFPicker() {
        pdfImportRequest = .manual
    }

    private func handleIncomingDocument(_ url: URL) {
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let isPDF = resourceType?.conforms(to: .pdf) == true
            || url.pathExtension.lowercased() == "pdf"

        guard url.isFileURL, isPDF else {
            incomingDocumentErrorMessage = "찬양서랍에는 PDF 파일만 추가할 수 있어요."
            return
        }

        guard pdfImportRequest == nil else {
            incomingDocumentErrorMessage = "현재 PDF 확인을 마친 뒤 다시 공유해 주세요."
            return
        }

        pdfImportRequest = PDFImportRequest(sourceURL: url)
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
