import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PDFImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var coordinator: PDFImportCoordinator
    @State private var isFileImporterPresented = false
    @State private var previewDocument: PDFPreviewDocument?
    @State private var isDiscardConfirmationPresented = false
    @State private var isReanalysisConfirmationPresented = false
    @State private var isReplacementConfirmationPresented = false

    private let initialPDFURL: URL?

    init(
        fileStore: any PDFFileStoring,
        pdfAnalyzer: any PDFAnalyzing = LocalPDFAnalyzer(),
        uploadScheduler: (any PDFAssetUploadScheduling)? = nil,
        initialPDFURL: URL? = nil
    ) {
        self.initialPDFURL = initialPDFURL
        _coordinator = State(
            initialValue: PDFImportCoordinator(
                fileStore: fileStore,
                pdfAnalyzer: pdfAnalyzer,
                uploadScheduler: uploadScheduler
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.phase {
                case .selecting:
                    selectionContent
                case .staging:
                    progressContent(
                        title: "PDF를 안전하게 복사하는 중",
                        message: "파일을 닫지 않아도 되도록 앱 보관함에 준비하고 있어요."
                    )
                case .analyzing:
                    analysisProgressContent
                case .reviewing:
                    PDFImportReviewForm(
                        coordinator: coordinator,
                        previewPDF: { pageNumber in
                            showPreview(startingAt: pageNumber)
                        },
                        selectAnotherPDF: {
                            isReplacementConfirmationPresented = true
                        },
                        retryAnalysis: {
                            isReanalysisConfirmationPresented = true
                        }
                    )
                case .saving:
                    progressContent(
                        title: "악보를 보관하는 중",
                        message: "원본 PDF와 곡 정보를 함께 저장하고 있어요."
                    )
                case .completed:
                    Color.clear
                }
            }
            .navigationTitle("PDF 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        requestCancellation()
                    }
                    .disabled(coordinator.phase == .saving)
                }

                if coordinator.phase == .reviewing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            save()
                        }
                        .disabled(!coordinator.canSave)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
        .sheet(item: $previewDocument) { document in
            PDFPreviewView(
                url: document.url,
                initialPageIndex: document.initialPageIndex
            )
        }
        .interactiveDismissDisabled(coordinator.hasPendingImport)
        .confirmationDialog(
            "가져오기를 취소할까요?",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("PDF와 편집 내용 버리기", role: .destructive) {
                cancelAndDismiss()
            }
            Button("계속 편집", role: .cancel) {}
        } message: {
            Text("아직 저장하지 않은 곡 제목, 키, 페이지 범위가 사라집니다.")
        }
        .confirmationDialog(
            "자동 분석을 다시 할까요?",
            isPresented: $isReanalysisConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("자동 제안으로 다시 만들기", role: .destructive) {
                retryAnalysis()
            }
            Button("현재 편집 유지", role: .cancel) {}
        } message: {
            Text("직접 수정한 곡 제목, 키, 페이지 범위가 새 자동 제안으로 바뀝니다.")
        }
        .confirmationDialog(
            "다른 PDF로 바꿀까요?",
            isPresented: $isReplacementConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("다른 PDF 선택", role: .destructive) {
                isFileImporterPresented = true
            }
            Button("현재 PDF 유지", role: .cancel) {}
        } message: {
            Text("새 PDF를 선택하면 현재 PDF의 곡 제목, 키, 페이지 범위 편집 내용은 사라집니다.")
        }
        .alert(
            "PDF를 처리할 수 없어요",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        coordinator.clearError()
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                coordinator.clearError()
            }
        } message: {
            Text(coordinator.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
        .task(id: initialPDFURL) {
            guard let initialPDFURL, coordinator.phase == .selecting else { return }
            await coordinator.stagePDF(
                from: initialPDFURL,
                in: modelContext.container
            )
        }
        .onDisappear {
            Task {
                await coordinator.cancel()
            }
        }
    }

    private var selectionContent: some View {
        ContentUnavailableView {
            Label("찬양 악보 PDF 선택", systemImage: "doc.badge.plus")
        } description: {
            Text("여러 곡이 들어 있는 PDF도 그대로 선택할 수 있어요.")
        } actions: {
            Button("파일 앱에서 선택") {
                isFileImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var analysisProgressContent: some View {
        let progress = coordinator.analysisProgress
        let title: String
        switch progress?.stage {
        case .extractingEmbeddedText:
            title = "PDF 글자 확인 중"
        case .recognizingText:
            title = "스캔 페이지 글자 인식 중"
        case .suggestingSongs:
            title = "곡 시작 페이지 찾는 중"
        case nil:
            title = "PDF 분석 준비 중"
        }

        let message: String
        if let progress, progress.totalPageCount > 0 {
            message = "\(progress.completedPageCount) / \(progress.totalPageCount)"
        } else {
            message = "페이지를 차례로 확인하고 있어요."
        }

        return progressContent(title: title, message: message)
    }

    private func progressContent(title: String, message: String) -> some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }
            Task {
                await coordinator.stagePDF(
                    from: sourceURL,
                    in: modelContext.container
                )
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                coordinator.errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        Task {
            let didSave = await coordinator.save(
                in: modelContext.container
            )
            if didSave {
                dismiss()
            }
        }
    }

    private func cancelAndDismiss() {
        Task {
            await coordinator.cancel()
            dismiss()
        }
    }

    private func requestCancellation() {
        if coordinator.hasPendingImport {
            isDiscardConfirmationPresented = true
        } else {
            dismiss()
        }
    }

    private func showPreview(startingAt pageNumber: Int?) {
        Task {
            guard let url = await coordinator.previewURL() else { return }
            previewDocument = PDFPreviewDocument(
                url: url,
                initialPageIndex: pageNumber.map { max(0, $0 - 1) }
            )
        }
    }

    private func retryAnalysis() {
        Task {
            await coordinator.retryAnalysis()
        }
    }
}

private struct PDFImportReviewForm: View {
    @Query(sort: \Song.title) private var existingSongs: [Song]
    @Bindable var coordinator: PDFImportCoordinator
    let previewPDF: (Int?) -> Void
    let selectAnotherPDF: () -> Void
    let retryAnalysis: () -> Void

    var body: some View {
        Form {
            if let stagedPDF = coordinator.stagedPDF {
                Section {
                    Label("자동 분석 결과를 확인해 주세요", systemImage: "checklist")
                        .font(.headline)

                    Text("곡 제목과 페이지 범위가 맞는지 확인한 뒤 저장하세요. 키가 확실하지 않으면 미지정으로 두어도 됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("원본 PDF") {
                    LabeledContent("파일", value: stagedPDF.originalFileName)
                    LabeledContent("페이지", value: "\(stagedPDF.pageCount)페이지")
                    LabeledContent(
                        "크기",
                        value: ByteCountFormatter.string(
                            fromByteCount: stagedPDF.fileSize,
                            countStyle: .file
                        )
                    )

                    Button {
                        previewPDF(nil)
                    } label: {
                        Label("원본 PDF 미리보기", systemImage: "doc.text.magnifyingglass")
                    }

                    Button("다른 PDF 선택") {
                        selectAnotherPDF()
                    }
                }

                Section("자동 분석") {
                    LabeledContent("찾은 곡", value: "\(coordinator.drafts.count)곡")

                    if let failedPageCount = coordinator.analysisResult?.failedPageCount,
                       failedPageCount > 0 {
                        Label(
                            "\(failedPageCount)개 페이지는 글자 인식을 확인해 주세요.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }

                    Button("다시 분석", action: retryAnalysis)
                }

                ForEach($coordinator.drafts) { $draft in
                    Section {
                        if let confidence = draft.suggestionConfidence {
                            Label(
                                confidence < 0.75 ? "확인 필요" : "자동으로 찾은 곡",
                                systemImage: confidence < 0.75
                                    ? "questionmark.circle"
                                    : "sparkles"
                            )
                            .font(.subheadline)
                            .foregroundStyle(confidence < 0.75 ? .orange : .secondary)
                        }

                        TextField("곡 제목", text: $draft.title)

                        if !existingSongs.isEmpty {
                            Picker("같은 곡 묶기", selection: $draft.existingSongID) {
                                Text("새 곡으로 저장").tag(nil as UUID?)
                                ForEach(existingSongs, id: \.id) { song in
                                    Text(song.title).tag(song.id as UUID?)
                                }
                            }
                            .onChange(of: draft.existingSongID) { _, songID in
                                guard let songID,
                                      let song = existingSongs.first(where: { $0.id == songID })
                                else { return }
                                draft.title = song.title
                            }
                        }

                        Picker("키", selection: $draft.musicalKey) {
                            Text("미지정").tag(nil as MusicalKey?)
                            ForEach(MusicalKey.allCases) { musicalKey in
                                Text(musicalKey.displayName)
                                    .tag(musicalKey as MusicalKey?)
                            }
                        }
                        .onChange(of: draft.musicalKey) { _, musicalKey in
                            draft.keySuggestionConfidence = nil
                            if draft.keySignatureChoice.musicalKey != musicalKey {
                                draft.keySignatureChoice = .unspecified
                            }
                        }

                        if let confidence = draft.keySuggestionConfidence,
                           let musicalKey = draft.musicalKey {
                            let detectionSummary = draft.keySignatureChoice == .unspecified
                                ? "\(musicalKey.displayName) 키"
                                : draft.keySignatureChoice.displayName
                            Label(
                                confidence < 0.75
                                    ? "\(detectionSummary)로 추정 · 확인 필요"
                                    : "\(detectionSummary)로 자동 감지",
                                systemImage: confidence < 0.75
                                    ? "questionmark.circle"
                                    : "music.note"
                            )
                            .font(.caption)
                            .foregroundStyle(confidence < 0.75 ? .orange : .secondary)
                        }

                        Button {
                            previewPDF(draft.startPageNumber)
                        } label: {
                            Label(
                                "이 곡 구간 미리보기",
                                systemImage: "doc.text.magnifyingglass"
                            )
                        }

                        pageInput(
                            title: "시작 페이지",
                            pageNumber: $draft.startPageNumber,
                            pageCount: stagedPDF.pageCount
                        )
                        pageInput(
                            title: "마지막 페이지",
                            pageNumber: $draft.endPageNumber,
                            pageCount: stagedPDF.pageCount
                        )

                        Button("이 곡 삭제", role: .destructive) {
                            coordinator.removeSongDraft(id: draft.id)
                        }
                    } header: {
                        Text(sectionTitle(for: draft))
                    }
                }

                Section {
                    Button {
                        coordinator.addSongDraft()
                    } label: {
                        Label("곡 추가", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("한 페이지에서 곡이 바뀌면 앞 곡의 마지막 페이지와 다음 곡의 시작 페이지를 같게 둘 수 있어요. 표지처럼 곡에 포함되지 않는 페이지는 비워 둘 수 있습니다.")
                }

                if let validationMessage = coordinator.validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func pageInput(
        title: String,
        pageNumber: Binding<Int>,
        pageCount: Int
    ) -> some View {
        let clampedPageNumber = Binding(
            get: { pageNumber.wrappedValue },
            set: { newValue in
                pageNumber.wrappedValue = min(max(newValue, 1), pageCount)
            }
        )

        return LabeledContent(title) {
            TextField("페이지", value: clampedPageNumber, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 44, maxWidth: 72)
                .accessibilityLabel(title)

            Stepper(
                title,
                value: clampedPageNumber,
                in: 1...pageCount
            )
            .labelsHidden()
            .accessibilityLabel("\(title) 조절")
        }
    }

    private func sectionTitle(for draft: SongDraft) -> String {
        guard let index = coordinator.drafts.firstIndex(where: { $0.id == draft.id }) else {
            return "곡"
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty
            ? "곡 \(index + 1) · 제목 확인 필요"
            : "곡 \(index + 1) · \(title)"
    }
}

private struct PDFPreviewDocument: Identifiable {
    let id = UUID()
    let url: URL
    let initialPageIndex: Int?
}
