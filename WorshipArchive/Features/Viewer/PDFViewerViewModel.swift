import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PDFViewerViewModel {
    let loader: PDFViewerLoader

    var loadRequestID = UUID()
    var currentPageIndex: Int?
    var persistenceErrorMessage: String?
    var isPerformanceMode = false
    var prefersTwoPageLayout = true
    var exportRequestID: UUID?
    var exportedSongPDF: ExportedSongPDF?
    var isExportingSongPDF = false
    var exportErrorMessage: String?
    var showsKeyEditor = false
    var showsSongManager = false
    var showsSongDeleteConfirmation = false
    var songManagementErrorMessage: String?

    @ObservationIgnored
    private let pdfExporter: SongPDFExporter
    @ObservationIgnored
    private let idleTimerCoordinator: PDFViewerIdleTimerCoordinator
    @ObservationIgnored
    private var idleTimerLease: UUID?

    init(
        fileAccess: any StoredPDFAccessing,
        documentLoader: any PDFDocumentLoading = LocalPDFDocumentLoader(),
        idleTimerCoordinator: PDFViewerIdleTimerCoordinator? = nil
    ) {
        loader = PDFViewerLoader(
            fileAccess: fileAccess,
            documentLoader: documentLoader
        )
        pdfExporter = SongPDFExporter(fileAccess: fileAccess)
        self.idleTimerCoordinator = idleTimerCoordinator ?? .shared
    }

    func viewerTitle(document: ArchiveDocument, sheet: SongSheet?) -> String {
        if let title = sheet?.song?.title, !title.isEmpty {
            return title
        }

        let fileName = URL(filePath: document.originalFileName)
            .deletingPathExtension()
            .lastPathComponent
        return fileName.isEmpty ? "악보" : fileName
    }

    func canExportSongPDF(sheet: SongSheet?) -> Bool {
        guard sheet != nil else { return false }
        if case .loaded = loader.phase {
            return true
        }
        return false
    }

    func retryLoading() {
        loadRequestID = UUID()
    }

    func requestSongPDFExport() {
        exportRequestID = UUID()
    }

    func deleteSong(
        _ song: Song?,
        in modelContext: ModelContext
    ) -> Bool {
        guard let song else {
            songManagementErrorMessage = "삭제할 곡 정보를 찾을 수 없어요."
            return false
        }

        do {
            try ArchiveLibraryEditing.deleteSong(song, in: modelContext)
            return true
        } catch {
            songManagementErrorMessage = error.localizedDescription
            return false
        }
    }

    func exportSongPDF(
        document: ArchiveDocument,
        sheet: SongSheet?
    ) async {
        guard let sheet else { return }

        isExportingSongPDF = true
        exportErrorMessage = nil
        defer {
            isExportingSongPDF = false
        }

        do {
            if let exportedSongPDF {
                await pdfExporter.remove(exportedSongPDF)
                self.exportedSongPDF = nil
            }

            let exportedPDF = try await pdfExporter.export(
                SongPDFExportRequest(
                    storedFileName: document.storedFileName,
                    checksum: document.checksum,
                    expectedPageCount: document.pageCount,
                    startPageIndex: sheet.startPageIndex,
                    endPageIndex: sheet.endPageIndex,
                    suggestedFileName: exportFileName(
                        for: sheet,
                        document: document
                    )
                )
            )
            if Task.isCancelled {
                await pdfExporter.remove(exportedPDF)
                return
            }
            exportedSongPDF = exportedPDF
        } catch is CancellationError {
            return
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    func removeExportedPDF(_ exportedPDF: ExportedSongPDF) async {
        if exportedSongPDF?.id == exportedPDF.id {
            exportedSongPDF = nil
        }
        await pdfExporter.remove(exportedPDF)
    }

    func selectPage(
        _ pageIndex: Int,
        in pageSession: PDFViewerPageSession,
        sheet: SongSheet?,
        modelContext: ModelContext
    ) {
        let clampedPageIndex = pageSession.clamped(pageIndex)
        guard currentPageIndex != clampedPageIndex else { return }

        currentPageIndex = clampedPageIndex
        recordPageChange(
            clampedPageIndex,
            sheet: sheet,
            modelContext: modelContext
        )
    }

    func loadDocument(
        document: ArchiveDocument,
        sheet: SongSheet?,
        modelContext: ModelContext
    ) async {
        currentPageIndex = nil
        guard let loadedDocument = await loader.load(
            document: document,
            sheet: sheet
        ) else {
            return
        }

        currentPageIndex = loadedDocument.pageSession.initialPageIndex

        guard let sheet else { return }

        do {
            try PDFViewerSessionPersistence.recordOpened(
                sheet: sheet,
                pageIndex: loadedDocument.pageSession.initialPageIndex,
                in: modelContext
            )
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    func updateIdleTimerLease(isSceneActive: Bool) {
        if isPerformanceMode, isSceneActive {
            guard idleTimerLease == nil else { return }
            idleTimerLease = idleTimerCoordinator.acquire()
        } else {
            releaseIdleTimerLease()
        }
    }

    func cancelViewing() {
        loader.cancel()
        releaseIdleTimerLease()
    }

    private func exportFileName(
        for sheet: SongSheet,
        document: ArchiveDocument
    ) -> String {
        let title = sheet.song?.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let baseName = (title?.isEmpty == false ? title : nil)
            ?? viewerTitle(document: document, sheet: sheet)
        guard let keyName = sheet.musicalKey?.displayName else {
            return baseName
        }
        return "\(baseName) (\(keyName))"
    }

    private func recordPageChange(
        _ pageIndex: Int,
        sheet: SongSheet?,
        modelContext: ModelContext
    ) {
        guard let sheet else { return }
        guard pageIndex != sheet.lastViewedPageIndex else { return }

        do {
            try PDFViewerSessionPersistence.recordPageChange(
                pageIndex,
                sheet: sheet,
                in: modelContext
            )
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func releaseIdleTimerLease() {
        guard let idleTimerLease else { return }
        idleTimerCoordinator.release(idleTimerLease)
        self.idleTimerLease = nil
    }
}
