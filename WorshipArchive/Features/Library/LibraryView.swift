import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]
    @Query(sort: \ArchiveDocument.importedAt, order: .reverse) private var documents: [ArchiveDocument]
    @State private var mode: LibraryMode = .songs
    @State private var showsFavoritesOnly = false
    @State private var favoriteSaveErrorMessage: String?
    @State private var documentPendingDeletion: ArchiveDocument?
    @State private var documentDeleteErrorMessage: String?

    let fileAccess: any PDFFileStoring
    let addPDF: () -> Void

    init(
        fileAccess: any PDFFileStoring = LocalPDFFileStore.live(),
        addPDF: @escaping () -> Void = {}
    ) {
        self.fileAccess = fileAccess
        self.addPDF = addPDF
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("라이브러리 보기", selection: $mode) {
                ForEach(LibraryMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.horizontal)

            if mode == .songs, !songs.isEmpty {
                HStack {
                    Toggle(isOn: $showsFavoritesOnly) {
                        Label("즐겨찾기만", systemImage: "heart.fill")
                    }
                    .toggleStyle(.button)
                    .tint(ArchiveTheme.accent)

                    Spacer()

                    Text("\(displayedSongs.count)곡")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 620)
                .padding(.horizontal)
            }

            ScrollView {
                libraryContent
                    .frame(maxWidth: 620)
                    .padding(.horizontal)
                    .padding(.bottom, 96)
            }
        }
        .padding(.top, 8)
        .background(ArchiveTheme.background)
        .navigationTitle("라이브러리")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addPDF) {
                    Label("PDF 추가", systemImage: "plus")
                }
            }
        }
        .alert(
            "즐겨찾기를 저장하지 못했어요",
            isPresented: favoriteErrorIsPresented
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(favoriteSaveErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .alert(
            "원본 PDF를 삭제하지 못했어요",
            isPresented: Binding(
                get: { documentDeleteErrorMessage != nil },
                set: { if !$0 { documentDeleteErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(documentDeleteErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .confirmationDialog(
            "원본 PDF와 연결된 악보를 삭제할까요?",
            isPresented: Binding(
                get: { documentPendingDeletion != nil },
                set: { if !$0 { documentPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: documentPendingDeletion
        ) { document in
            Button("삭제", role: .destructive) { delete(document) }
            Button("취소", role: .cancel) {}
        } message: { document in
            Text("‘\(document.originalFileName)’과 이 PDF에만 연결된 곡이 함께 삭제됩니다.")
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch mode {
        case .songs:
            if songs.isEmpty {
                emptyState
            } else if displayedSongs.isEmpty {
                ArchiveEmptyState(
                    systemImage: "heart",
                    title: "즐겨찾기한 곡이 없어요",
                    message: "자주 보는 곡의 하트를 눌러 이곳에 모아 보세요."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(displayedSongs, id: \.id) { song in
                        SongLibraryRow(
                            title: song.title,
                            subtitle: keySummary(for: song),
                            isFavorite: song.isFavorite,
                            toggleFavorite: {
                                toggleFavorite(for: song)
                            }
                        ) {
                            SongDetailView(song: song, fileAccess: fileAccess)
                        }
                    }
                }
            }
        case .documents:
            if documents.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(documents, id: \.id) { document in
                        NavigationLink {
                            PDFViewerView(
                                document: document,
                                sheet: nil,
                                fileAccess: fileAccess
                            )
                        } label: {
                            LibraryItemRow(
                                title: document.originalFileName,
                                subtitle: "\(document.pageCount)페이지",
                                systemImage: "doc.richtext"
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("삭제", systemImage: "trash", role: .destructive) {
                                documentPendingDeletion = document
                            }
                        }
                    }
                }
            }
        }
    }

    private var displayedSongs: [Song] {
        SongSearchMatcher.filter(
            songs,
            using: SongSearchFilter(favoritesOnly: showsFavoritesOnly)
        )
    }

    private var favoriteErrorIsPresented: Binding<Bool> {
        Binding(
            get: { favoriteSaveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    favoriteSaveErrorMessage = nil
                }
            }
        )
    }

    private var emptyState: some View {
        ArchiveEmptyState(
            systemImage: mode.systemImage,
            title: mode.emptyTitle,
            message: mode.emptyMessage,
            actionTitle: "PDF 추가",
            actionSystemImage: "plus",
            action: addPDF
        )
    }

    private func keySummary(for song: Song) -> String {
        let keyNames = Set(
            song.sheets?.compactMap { $0.musicalKey?.displayName } ?? []
        ).sorted()

        switch keyNames.count {
        case 0:
            return "키 미지정"
        case 1...2:
            return keyNames.joined(separator: " · ")
        default:
            return "\(keyNames[0]) 외 \(keyNames.count - 1)개 키"
        }
    }

    private func toggleFavorite(for song: Song) {
        let previousValue = song.isFavorite
        song.isFavorite.toggle()

        do {
            try modelContext.save()
        } catch {
            song.isFavorite = previousValue
            favoriteSaveErrorMessage = error.localizedDescription
        }
    }

    private func delete(_ document: ArchiveDocument) {
        do {
            let storedFileName = try ArchiveLibraryEditing.deleteDocument(
                document,
                in: modelContext
            )
            documentPendingDeletion = nil
            Task {
                do {
                    try await fileAccess.removeStoredFile(named: storedFileName)
                } catch PDFFileStoreError.storedFileMissing {
                    // The requested final state is already satisfied.
                } catch {
                    documentDeleteErrorMessage = "목록에서는 삭제했지만 기기 파일 정리가 남았습니다. 앱이 다음 정리 작업에서 다시 처리합니다."
                }
            }
        } catch {
            documentPendingDeletion = nil
            documentDeleteErrorMessage = error.localizedDescription
        }
    }
}

private struct LibraryItemRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ArchiveTheme.tint)
                .frame(width: 44, height: 44)
                .background(ArchiveTheme.tint.opacity(0.12), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(ArchiveTheme.surface, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("원본 PDF를 엽니다")
    }
}

private enum LibraryMode: String, CaseIterable, Identifiable {
    case songs
    case documents

    var id: Self { self }

    var title: String {
        switch self {
        case .songs: "곡별"
        case .documents: "PDF별"
        }
    }

    var systemImage: String {
        switch self {
        case .songs: "music.note.list"
        case .documents: "doc.richtext"
        }
    }

    var emptyTitle: String {
        switch self {
        case .songs: "등록된 곡이 없어요"
        case .documents: "보관 중인 PDF가 없어요"
        }
    }

    var emptyMessage: String {
        switch self {
        case .songs: "PDF 분석을 확인하면 곡별 악보가 여기에 모여요."
        case .documents: "가져온 원본 PDF를 변경 없이 안전하게 보관해요."
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(AppModelContainer.preview)
}
