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
    @Environment(\.modelContext) private var modelContext

    @State private var selection: AppDestination = .home
    @State private var isPDFImportPresented = false
    @State private var didPerformFileMaintenance = false

    private let fileStore: any PDFFileStoring
    private let pdfAnalyzer: any PDFAnalyzing
    private let performsFileMaintenance: Bool

    init(
        fileStore: any PDFFileStoring = LocalPDFFileStore.live(),
        pdfAnalyzer: any PDFAnalyzing = LocalPDFAnalyzer(),
        performsFileMaintenance: Bool = true
    ) {
        self.fileStore = fileStore
        self.pdfAnalyzer = pdfAnalyzer
        self.performsFileMaintenance = performsFileMaintenance
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(
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
                SearchView()
            }
            .tabItem {
                Label(AppDestination.search.title, systemImage: AppDestination.search.systemImage)
            }
            .tag(AppDestination.search)

            NavigationStack {
                LibraryView {
                    isPDFImportPresented = true
                }
            }
            .tabItem {
                Label(AppDestination.library.title, systemImage: AppDestination.library.systemImage)
            }
            .tag(AppDestination.library)

            NavigationStack {
                SettingsView()
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
                pdfAnalyzer: pdfAnalyzer
            )
        }
        .task {
            await performFileMaintenanceIfNeeded()
        }
    }

    private func performFileMaintenanceIfNeeded() async {
        guard performsFileMaintenance, !didPerformFileMaintenance else { return }
        didPerformFileMaintenance = true
        guard await ArchiveFileMaintenanceGate.shared.beginIfNeeded() else { return }

        let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60)
        try? await fileStore.removeStaleStagedFiles(olderThan: cutoffDate)

        let documents: [ArchiveDocument]
        do {
            documents = try modelContext.fetch(FetchDescriptor<ArchiveDocument>())
        } catch {
            return
        }

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
