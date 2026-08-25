import Observation
import PDFKit
import SwiftData
import SwiftUI
import UIKit

struct PDFViewerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    let document: ArchiveDocument
    let sheet: SongSheet?
    private let fileAccess: any StoredPDFAccessing

    @State private var loader: PDFViewerLoader
    @State private var loadRequestID = UUID()
    @State private var currentPageIndex: Int?
    @State private var persistenceErrorMessage: String?
    @State private var isPerformanceMode = false
    @State private var prefersTwoPageLayout = true
    @State private var idleTimerLease: UUID?
    @State private var pdfExporter: SongPDFExporter
    @State private var exportRequestID: UUID?
    @State private var exportedSongPDF: ExportedSongPDF?
    @State private var isExportingSongPDF = false
    @State private var exportErrorMessage: String?

    init(
        document: ArchiveDocument,
        sheet: SongSheet?,
        fileAccess: any StoredPDFAccessing = LocalPDFFileStore.live()
    ) {
        self.document = document
        self.sheet = sheet
        self.fileAccess = fileAccess
        _loader = State(
            initialValue: PDFViewerLoader(fileAccess: fileAccess)
        )
        _pdfExporter = State(
            initialValue: SongPDFExporter(fileAccess: fileAccess)
        )
    }

    var body: some View {
        Group {
            switch loader.phase {
            case .idle, .loading:
                ProgressView("악보를 여는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let loadedDocument):
                scoreViewer(for: loadedDocument)

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
        .toolbar {
            if sheet != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    if isExportingSongPDF {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("곡 PDF 만드는 중")
                    } else {
                        Button("곡 PDF 공유", systemImage: "square.and.arrow.up") {
                            exportRequestID = UUID()
                        }
                        .disabled(!canExportSongPDF)
                    }

                    if let song = sheet?.song {
                        NavigationLink {
                            SongDetailView(
                                song: song,
                                fileAccess: fileAccess
                            )
                        } label: {
                            Label("곡 관리", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .toolbar(isPerformanceMode ? .hidden : .visible, for: .navigationBar)
        .persistentSystemOverlays(isPerformanceMode ? .hidden : .automatic)
        .task(id: loadRequestID) {
            await loadDocument()
        }
        .task(id: exportRequestID) {
            guard exportRequestID != nil else { return }
            await exportSongPDF()
        }
        .onAppear {
            updateIdleTimerLease(
                performanceModeIsEnabled: isPerformanceMode,
                scenePhase: scenePhase
            )
        }
        .onChange(of: isPerformanceMode) { _, isEnabled in
            updateIdleTimerLease(
                performanceModeIsEnabled: isEnabled,
                scenePhase: scenePhase
            )
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            updateIdleTimerLease(
                performanceModeIsEnabled: isPerformanceMode,
                scenePhase: newScenePhase
            )
        }
        .onDisappear {
            loader.cancel()
            releaseIdleTimerLease()
            if let exportedSongPDF {
                Task {
                    await pdfExporter.remove(exportedSongPDF)
                }
            }
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
        .alert(
            "곡 PDF를 만들지 못했어요",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        exportErrorMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .sheet(item: $exportedSongPDF) { exportedPDF in
            PDFShareSheet(fileURL: exportedPDF.fileURL) {
                exportedSongPDF = nil
                Task {
                    await pdfExporter.remove(exportedPDF)
                }
            }
            .onDisappear {
                Task {
                    await pdfExporter.remove(exportedPDF)
                }
            }
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

    private var canExportSongPDF: Bool {
        guard sheet != nil else { return false }
        if case .loaded = loader.phase {
            return true
        }
        return false
    }

    private func exportSongPDF() async {
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
                    suggestedFileName: exportFileName(for: sheet)
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

    private func exportFileName(for sheet: SongSheet) -> String {
        let title = sheet.song?.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let baseName = (title?.isEmpty == false ? title : nil) ?? viewerTitle
        guard let keyName = sheet.musicalKey?.displayName else {
            return baseName
        }
        return "\(baseName) (\(keyName))"
    }

    private func scoreViewer(
        for loadedDocument: PDFViewerLoadedDocument
    ) -> some View {
        let pageSession = loadedDocument.pageSession
        let displayedPageIndex = pageSession.clamped(
            currentPageIndex ?? pageSession.initialPageIndex
        )

        return GeometryReader { proxy in
            let allowsTwoPageLayout = horizontalSizeClass == .regular
                && proxy.size.width > proxy.size.height
                && pageSession.pageCount > 1
            let usesTwoPageLayout = allowsTwoPageLayout && prefersTwoPageLayout
            let pageSpan = usesTwoPageLayout ? 2 : 1

            Group {
                if usesTwoPageLayout {
                    PDFKitTwoPageScoreView(
                        document: loadedDocument.document,
                        pageSession: pageSession,
                        currentPageIndex: displayedPageIndex
                    )
                } else {
                    PDFKitScoreView(
                        document: loadedDocument.document,
                        pageSession: pageSession,
                        currentPageIndex: displayedPageIndex,
                        onPageChanged: { pageIndex in
                            selectPage(pageIndex, in: pageSession)
                        }
                    )
                }
            }
            .ignoresSafeArea(edges: isPerformanceMode ? .all : .bottom)
            .overlay(alignment: .bottom) {
                PDFViewerPageControls(
                    pageSession: pageSession,
                    currentPageIndex: displayedPageIndex,
                    pageSpan: pageSpan,
                    allowsTwoPageLayout: allowsTwoPageLayout,
                    usesTwoPageLayout: usesTwoPageLayout,
                    isPerformanceMode: isPerformanceMode,
                    selectPage: { pageIndex in
                        selectPage(pageIndex, in: pageSession)
                    },
                    toggleTwoPageLayout: {
                        prefersTwoPageLayout.toggle()
                    },
                    togglePerformanceMode: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPerformanceMode.toggle()
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, isPerformanceMode ? 20 : 12)
            }
        }
    }

    private func selectPage(
        _ pageIndex: Int,
        in pageSession: PDFViewerPageSession
    ) {
        let clampedPageIndex = pageSession.clamped(pageIndex)
        guard currentPageIndex != clampedPageIndex else { return }

        currentPageIndex = clampedPageIndex
        recordPageChange(clampedPageIndex)
    }

    private func loadDocument() async {
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

    private func updateIdleTimerLease(
        performanceModeIsEnabled: Bool,
        scenePhase: ScenePhase
    ) {
        if performanceModeIsEnabled, scenePhase == .active {
            guard idleTimerLease == nil else { return }
            idleTimerLease = PDFViewerIdleTimerCoordinator.shared.acquire()
        } else {
            releaseIdleTimerLease()
        }
    }

    private func releaseIdleTimerLease() {
        guard let idleTimerLease else { return }
        PDFViewerIdleTimerCoordinator.shared.release(idleTimerLease)
        self.idleTimerLease = nil
    }
}

@MainActor
final class PDFViewerIdleTimerCoordinator {
    static let shared = PDFViewerIdleTimerCoordinator(
        readValue: { UIApplication.shared.isIdleTimerDisabled },
        writeValue: { UIApplication.shared.isIdleTimerDisabled = $0 }
    )

    private let readValue: () -> Bool
    private let writeValue: (Bool) -> Void
    private var activeLeases: Set<UUID> = []
    private var valueBeforeFirstLease: Bool?

    init(
        readValue: @escaping () -> Bool,
        writeValue: @escaping (Bool) -> Void
    ) {
        self.readValue = readValue
        self.writeValue = writeValue
    }

    func acquire() -> UUID {
        let lease = UUID()
        if activeLeases.isEmpty {
            valueBeforeFirstLease = readValue()
            writeValue(true)
        }
        activeLeases.insert(lease)
        return lease
    }

    func release(_ lease: UUID) {
        guard activeLeases.remove(lease) != nil else { return }
        guard activeLeases.isEmpty, let valueBeforeFirstLease else { return }

        self.valueBeforeFirstLease = nil
        writeValue(valueBeforeFirstLease)
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

    var pageCount: Int {
        endPageIndex - startPageIndex + 1
    }

    func relativePageNumber(for pageIndex: Int) -> Int {
        clamped(pageIndex) - startPageIndex + 1
    }

    func previousPageIndex(from pageIndex: Int) -> Int {
        previousPageIndex(from: pageIndex, pageSpan: 1)
    }

    func nextPageIndex(from pageIndex: Int) -> Int {
        nextPageIndex(from: pageIndex, pageSpan: 1)
    }

    func pageGroupStart(containing pageIndex: Int, pageSpan: Int) -> Int {
        let normalizedSpan = max(pageSpan, 1)
        let offset = clamped(pageIndex) - startPageIndex
        return startPageIndex + (offset / normalizedSpan) * normalizedSpan
    }

    func visiblePageIndices(
        containing pageIndex: Int,
        pageSpan: Int
    ) -> [Int] {
        let normalizedSpan = max(pageSpan, 1)
        let groupStart = pageGroupStart(
            containing: pageIndex,
            pageSpan: normalizedSpan
        )
        let groupEnd = min(groupStart + normalizedSpan - 1, endPageIndex)
        return Array(groupStart...groupEnd)
    }

    func previousPageIndex(from pageIndex: Int, pageSpan: Int) -> Int {
        let normalizedSpan = max(pageSpan, 1)
        let groupStart = pageGroupStart(
            containing: pageIndex,
            pageSpan: normalizedSpan
        )
        return max(groupStart - normalizedSpan, startPageIndex)
    }

    func nextPageIndex(from pageIndex: Int, pageSpan: Int) -> Int {
        let normalizedSpan = max(pageSpan, 1)
        let groupStart = pageGroupStart(
            containing: pageIndex,
            pageSpan: normalizedSpan
        )
        return min(groupStart + normalizedSpan, endPageIndex)
    }
}

private struct PDFViewerPageControls: View {
    let pageSession: PDFViewerPageSession
    let currentPageIndex: Int
    let pageSpan: Int
    let allowsTwoPageLayout: Bool
    let usesTwoPageLayout: Bool
    let isPerformanceMode: Bool
    let selectPage: (Int) -> Void
    let toggleTwoPageLayout: () -> Void
    let togglePerformanceMode: () -> Void

    private var visiblePageIndices: [Int] {
        pageSession.visiblePageIndices(
            containing: currentPageIndex,
            pageSpan: pageSpan
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            pageButton(
                title: "이전 페이지",
                systemImage: "chevron.left",
                isEnabled: visiblePageIndices.first != pageSession.startPageIndex
            ) {
                selectPage(
                    pageSession.previousPageIndex(
                        from: currentPageIndex,
                        pageSpan: pageSpan
                    )
                )
            }

            Text(pageDisplayText)
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .frame(minWidth: 64)
            .accessibilityLabel(pageAccessibilityLabel)

            pageButton(
                title: "다음 페이지",
                systemImage: "chevron.right",
                isEnabled: visiblePageIndices.last != pageSession.endPageIndex
            ) {
                selectPage(
                    pageSession.nextPageIndex(
                        from: currentPageIndex,
                        pageSpan: pageSpan
                    )
                )
            }

            Divider()
                .frame(height: 22)

            if allowsTwoPageLayout {
                pageButton(
                    title: usesTwoPageLayout ? "한 페이지로 보기" : "두 페이지로 보기",
                    systemImage: usesTwoPageLayout ? "rectangle" : "rectangle.split.2x1",
                    isEnabled: true,
                    action: toggleTwoPageLayout
                )
            }

            pageButton(
                title: isPerformanceMode ? "전체 화면 종료" : "전체 화면 연주",
                systemImage: isPerformanceMode
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                isEnabled: true,
                action: togglePerformanceMode
            )

            Divider()
                .frame(height: 22)

            ViewThatFits(in: .horizontal) {
                Label("오프라인 저장", systemImage: "internaldrive.fill")
                    .font(.caption.weight(.medium))

                Image(systemName: "internaldrive.fill")
                    .accessibilityLabel("오프라인 저장")
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay {
            Capsule()
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private var pageAccessibilityLabel: String {
        let relativePages = visiblePageIndices.map {
            String(pageSession.relativePageNumber(for: $0))
        }.joined(separator: "에서 ")
        let originalPages = visiblePageIndices.map {
            String($0 + 1)
        }.joined(separator: "에서 ")
        return "악보 \(relativePages) / \(pageSession.pageCount)페이지, 원본 \(originalPages)페이지"
    }

    private var pageDisplayText: String {
        let relativePages = visiblePageIndices.map {
            pageSession.relativePageNumber(for: $0)
        }
        guard let firstPage = relativePages.first else {
            return "1 / \(pageSession.pageCount)"
        }
        guard let lastPage = relativePages.last, lastPage != firstPage else {
            return "\(firstPage) / \(pageSession.pageCount)"
        }
        return "\(firstPage)–\(lastPage) / \(pageSession.pageCount)"
    }

    private func pageButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? ArchiveTheme.tint : Color.secondary.opacity(0.35))
        .accessibilityLabel(title)
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
