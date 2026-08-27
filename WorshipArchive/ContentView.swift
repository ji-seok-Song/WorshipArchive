import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \ArchiveDocument.importedAt) private var documents: [ArchiveDocument]

    @State private var viewModel = AppViewModel()

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
        @Bindable var viewModel = viewModel
        let syncAssets = viewModel.syncAssets(from: documents)

        TabView(selection: $viewModel.selection) {
            NavigationStack {
                HomeView(
                    fileAccess: fileStore,
                    navigate: { destination in
                        viewModel.selection = destination
                    },
                    addPDF: {
                        viewModel.presentPDFPicker()
                    }
                )
            }
            .tabItem {
                Label(AppDestination.home.title, systemImage: AppDestination.home.systemImage)
            }
            .tag(AppDestination.home)

            NavigationStack {
                LibraryView(fileAccess: fileStore) {
                    viewModel.presentPDFPicker()
                }
            }
            .tabItem {
                Label(AppDestination.library.title, systemImage: AppDestination.library.systemImage)
            }
            .tag(AppDestination.library)
            
            NavigationStack {
                SearchView(fileAccess: fileStore) {
                    viewModel.presentPDFPicker()
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
        .sheet(item: $viewModel.pdfImportRequest) { request in
            PDFImportView(
                fileStore: fileStore,
                pdfAnalyzer: pdfAnalyzer,
                uploadScheduler: syncCoordinator,
                initialPDFURL: request.sourceURL
            )
        }
        .onOpenURL(perform: viewModel.handleIncomingDocument)
        .alert(
            "PDF를 열 수 없어요",
            isPresented: Binding(
                get: { viewModel.incomingDocumentErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.incomingDocumentErrorMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                viewModel.incomingDocumentErrorMessage = nil
            }
        } message: {
            Text(viewModel.incomingDocumentErrorMessage ?? "PDF 파일인지 확인해 주세요.")
        }
        .task {
            await viewModel.performFileMaintenanceIfNeeded(
                documents: documents,
                fileStore: fileStore,
                usesCloudSync: syncCoordinator != nil,
                isEnabled: performsFileMaintenance
            )
        }
        .task(id: syncAssets) {
            await syncCoordinator?.reconcile(syncAssets)
        }
    }
}

#Preview {
    ContentView(performsFileMaintenance: false)
        .modelContainer(AppModelContainer.preview)
}
