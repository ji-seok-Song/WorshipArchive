import Observation
import PDFKit
import SwiftData
import SwiftUI

struct PDFViewerView: View {
    @Environment(\.modelContext) private var modelContext

    let document: ArchiveDocument
    let sheet: SongSheet?

    @State private var loader: PDFViewerLoader
    @State private var loadRequestID = UUID()
    @State private var persistenceErrorMessage: String?

    init(
        document: ArchiveDocument,
        sheet: SongSheet?,
        fileAccess: any StoredPDFAccessing = LocalPDFFileStore.live()
    ) {
        self.document = document
        self.sheet = sheet
        _loader = State(
            initialValue: PDFViewerLoader(fileAccess: fileAccess)
        )
    }

    var body: some View {
        Group {
            switch loader.phase {
            case .idle, .loading:
                ProgressView("악보를 여는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let loadedDocument):
                PDFKitScoreView(
                    document: loadedDocument.document,
                    pageSession: loadedDocument.pageSession,
                    onPageChanged: recordPageChange
                )
                .ignoresSafeArea(edges: .bottom)

            case .failed(let message):
                ContentUnavailableView {
                    Label("악보를 열 수 없어요", systemImage: "doc.badge.ellipsis")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도") {
                        loadRequestID = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(viewerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRequestID) {
            await loadDocument()
        }
        .onDisappear {
            loader.cancel()
        }
        .alert(
            "열람 기록을 저장하지 못했어요",
            isPresented: Binding(
                get: { persistenceErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        persistenceErrorMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                persistenceErrorMessage = nil
            }
        } message: {
            Text(persistenceErrorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
    }

    private var viewerTitle: String {
        if let title = sheet?.song?.title, !title.isEmpty {
            return title
        }

        let fileName = URL(filePath: document.originalFileName)
            .deletingPathExtension()
            .lastPathComponent
        return fileName.isEmpty ? "악보" : fileName
    }

    private func loadDocument() async {
        guard let loadedDocument = await loader.load(
            document: document,
            sheet: sheet
        ) else {
            return
        }

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

    private func recordPageChange(_ pageIndex: Int) {
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
}

@MainActor
@Observable
final class PDFViewerLoader {
    enum Phase {
        case idle
        case loading
        case loaded(PDFViewerLoadedDocument)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    @ObservationIgnored
    private let fileAccess: any StoredPDFAccessing
    @ObservationIgnored
    private let documentLoader: any PDFDocumentLoading
    @ObservationIgnored
    private var operationID: UUID?
    @ObservationIgnored
    private var activeLoadTask: Task<PDFViewerLoadedDocument, Error>?

    init(
        fileAccess: any StoredPDFAccessing,
        documentLoader: any PDFDocumentLoading = LocalPDFDocumentLoader()
    ) {
        self.fileAccess = fileAccess
        self.documentLoader = documentLoader
    }

    @discardableResult
    func load(
        document: ArchiveDocument,
        sheet: SongSheet?
    ) async -> PDFViewerLoadedDocument? {
        activeLoadTask?.cancel()

        let currentOperationID = UUID()
        operationID = currentOperationID
        phase = .loading

        do {
            let request = try makeLoadRequest(
                document: document,
                sheet: sheet
            )
            let loadTask = Task { [fileAccess, documentLoader] in
                let fileURL = try await fileAccess.storedFileURL(
                    named: request.storedFileName,
                    expectedChecksum: request.checksum
                )
                try Task.checkCancellation()

                return try await documentLoader.load(
                    fileAt: fileURL,
                    expectedPageCount: request.documentPageCount,
                    pageSession: request.pageSession
                )
            }
            activeLoadTask = loadTask
            let loadedDocument = try await withTaskCancellationHandler {
                try await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }
            try Task.checkCancellation()
            guard operationID == currentOperationID else { return nil }

            activeLoadTask = nil
            operationID = nil
            phase = .loaded(loadedDocument)
            return loadedDocument
        } catch is CancellationError {
            guard operationID == currentOperationID else { return nil }
            activeLoadTask = nil
            operationID = nil
            phase = .idle
            return nil
        } catch {
            guard operationID == currentOperationID else { return nil }
            activeLoadTask = nil
            operationID = nil
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    func cancel() {
        operationID = nil
        activeLoadTask?.cancel()
        activeLoadTask = nil
        phase = .idle
    }

    private func makeLoadRequest(
        document: ArchiveDocument,
        sheet: SongSheet?
    ) throws -> PDFViewerLoadRequest {
        if let sheet, sheet.document?.id != document.id {
            throw PDFViewerError.sheetDocumentMismatch
        }

        let pageSession: PDFViewerPageSession
        if let sheet {
            pageSession = try PDFViewerPageSession(
                startPageIndex: sheet.startPageIndex,
                endPageIndex: sheet.endPageIndex,
                lastViewedPageIndex: sheet.lastViewedPageIndex,
                documentPageCount: document.pageCount
            )
        } else {
            guard document.pageCount > 0 else {
                throw PDFViewerError.invalidPageRange
            }
            pageSession = try PDFViewerPageSession(
                startPageIndex: 0,
                endPageIndex: document.pageCount - 1,
                lastViewedPageIndex: 0,
                documentPageCount: document.pageCount
            )
        }

        return PDFViewerLoadRequest(
            storedFileName: document.storedFileName,
            checksum: document.checksum,
            documentPageCount: document.pageCount,
            pageSession: pageSession
        )
    }
}

nonisolated struct PDFViewerLoadRequest: Equatable, Sendable {
    let storedFileName: String
    let checksum: String
    let documentPageCount: Int
    let pageSession: PDFViewerPageSession
}

nonisolated protocol PDFDocumentLoading: Sendable {
    func load(
        fileAt fileURL: URL,
        expectedPageCount: Int,
        pageSession: PDFViewerPageSession
    ) async throws -> PDFViewerLoadedDocument
}

actor LocalPDFDocumentLoader: PDFDocumentLoading {
    func load(
        fileAt fileURL: URL,
        expectedPageCount: Int,
        pageSession: PDFViewerPageSession
    ) async throws -> PDFViewerLoadedDocument {
        try Task.checkCancellation()
        guard fileURL.isFileURL else {
            throw PDFViewerError.invalidStoredURL
        }
        let isRegularFile = try fileURL.resourceValues(
            forKeys: [.isRegularFileKey]
        ).isRegularFile
        guard isRegularFile == true else {
            throw PDFViewerError.invalidStoredURL
        }
        try Task.checkCancellation()

        guard let pdfDocument = PDFDocument(url: fileURL) else {
            throw PDFViewerError.documentCannotBeOpened
        }
        try Task.checkCancellation()
        guard pdfDocument.pageCount == expectedPageCount else {
            throw PDFViewerError.pageCountChanged
        }

        return PDFViewerLoadedDocument(
            document: pdfDocument,
            pageSession: pageSession
        )
    }
}

nonisolated struct PDFViewerLoadedDocument: @unchecked Sendable {
    let document: PDFDocument
    let pageSession: PDFViewerPageSession
}

nonisolated struct PDFViewerPageSession: Equatable, Sendable {
    let startPageIndex: Int
    let endPageIndex: Int
    let initialPageIndex: Int

    init(
        startPageIndex: Int,
        endPageIndex: Int,
        lastViewedPageIndex: Int,
        documentPageCount: Int
    ) throws {
        guard
            documentPageCount > 0,
            startPageIndex >= 0,
            startPageIndex <= endPageIndex,
            endPageIndex < documentPageCount
        else {
            throw PDFViewerError.invalidPageRange
        }

        self.startPageIndex = startPageIndex
        self.endPageIndex = endPageIndex
        initialPageIndex = min(
            max(lastViewedPageIndex, startPageIndex),
            endPageIndex
        )
    }

    func clamped(_ pageIndex: Int) -> Int {
        min(max(pageIndex, startPageIndex), endPageIndex)
    }
}

@MainActor
enum PDFViewerSessionPersistence {
    static func recordOpened(
        sheet: SongSheet,
        pageIndex: Int,
        at date: Date = Date(),
        in context: ModelContext
    ) throws {
        try recordActivity(
            sheet: sheet,
            pageIndex: pageIndex,
            at: date,
            in: context
        )
    }

    static func recordPageChange(
        _ pageIndex: Int,
        sheet: SongSheet,
        at date: Date = Date(),
        in context: ModelContext
    ) throws {
        try recordActivity(
            sheet: sheet,
            pageIndex: pageIndex,
            at: date,
            in: context
        )
    }

    private static func recordActivity(
        sheet: SongSheet,
        pageIndex: Int,
        at date: Date,
        in context: ModelContext
    ) throws {
        try recordActivity(
            sheet: sheet,
            pageIndex: pageIndex,
            at: date,
            save: context.save
        )
    }

    static func recordActivity(
        sheet: SongSheet,
        pageIndex: Int,
        at date: Date,
        save: () throws -> Void
    ) throws {
        let previousPageIndex = sheet.lastViewedPageIndex
        let previousSheetOpenedAt = sheet.lastOpenedAt
        let song = sheet.song
        let previousSongOpenedAt = song?.lastOpenedAt

        sheet.updateLastViewedPageIndex(pageIndex)
        sheet.lastOpenedAt = date
        song?.lastOpenedAt = date

        do {
            try save()
        } catch {
            sheet.updateLastViewedPageIndex(previousPageIndex)
            sheet.lastOpenedAt = previousSheetOpenedAt
            song?.lastOpenedAt = previousSongOpenedAt
            throw error
        }
    }
}

nonisolated enum PDFViewerError: LocalizedError, Equatable {
    case sheetDocumentMismatch
    case invalidPageRange
    case invalidStoredURL
    case documentCannotBeOpened
    case pageCountChanged

    var errorDescription: String? {
        switch self {
        case .sheetDocumentMismatch:
            "곡과 원본 PDF의 연결을 확인할 수 없습니다."
        case .invalidPageRange:
            "곡의 페이지 범위가 원본 PDF와 맞지 않습니다."
        case .invalidStoredURL:
            "보관된 PDF의 안전한 파일 경로를 확인할 수 없습니다."
        case .documentCannotBeOpened:
            "보관된 PDF를 열 수 없습니다."
        case .pageCountChanged:
            "보관된 PDF의 페이지 수가 저장 정보와 다릅니다."
        }
    }
}
