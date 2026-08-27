import SwiftData
import SwiftUI

struct SongDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let song: Song
    let fileAccess: any StoredPDFAccessing

    @State private var viewModel = SongDetailViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        SongDetailContent(
            song: song,
            sheets: viewModel.sortedSheets(for: song),
            fileAccess: fileAccess,
            editSheet: { viewModel.sheetBeingEdited = $0 },
            deleteSheet: { viewModel.sheetPendingDeletion = $0 }
        )
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.toggleFavorite(for: song, in: modelContext)
                } label: {
                    Label(
                        song.isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가",
                        systemImage: song.isFavorite ? "heart.fill" : "heart"
                    )
                }
                .tint(song.isFavorite ? ArchiveTheme.accent : ArchiveTheme.tint)

                Menu {
                    Button("곡 정보 수정", systemImage: "pencil") {
                        viewModel.showsSongEditor = true
                    }
                    Button("다른 곡과 묶기", systemImage: "arrow.triangle.merge") {
                        viewModel.showsSongMergeForm = true
                    }
                    Button("곡 삭제", systemImage: "trash", role: .destructive) {
                        viewModel.showsSongDeleteConfirmation = true
                    }
                } label: {
                    Label("더 보기", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert(
            "즐겨찾기를 저장하지 못했어요",
            isPresented: Binding(
                get: { viewModel.favoriteSaveErrorMessage != nil },
                set: { if !$0 { viewModel.favoriteSaveErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.favoriteSaveErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .alert(
            "변경 사항을 저장하지 못했어요",
            isPresented: Binding(
                get: { viewModel.archiveEditErrorMessage != nil },
                set: { if !$0 { viewModel.archiveEditErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.archiveEditErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .confirmationDialog(
            "이 악보를 곡에서 삭제할까요?",
            isPresented: Binding(
                get: { viewModel.sheetPendingDeletion != nil },
                set: { if !$0 { viewModel.sheetPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.sheetPendingDeletion
        ) { sheet in
            Button("삭제", role: .destructive) {
                viewModel.delete(sheet, in: modelContext)
            }
            Button("취소", role: .cancel) {}
        } message: { sheet in
            Text("원본 PDF는 유지되고 \(sheet.startPageIndex + 1)~\(sheet.endPageIndex + 1)페이지 연결만 삭제됩니다.")
        }
        .confirmationDialog(
            "‘\(song.title)’을 삭제할까요?",
            isPresented: $viewModel.showsSongDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("곡 삭제", role: .destructive) {
                if viewModel.delete(song, in: modelContext) {
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("곡에 연결된 악보가 함께 삭제됩니다. 원본 PDF는 유지됩니다.")
        }
        .sheet(isPresented: $viewModel.showsSongEditor) {
            NavigationStack {
                SongEditForm(song: song)
            }
        }
        .sheet(isPresented: $viewModel.showsSongMergeForm) {
            NavigationStack {
                SongMergeForm(sourceSong: song) {
                    dismiss()
                }
            }
        }
        .sheet(item: $viewModel.sheetBeingEdited) { sheet in
            NavigationStack {
                SongSheetEditForm(sheet: sheet)
            }
        }
    }

}

private struct SongDetailContent: View {
    let song: Song
    let sheets: [SongSheet]
    let fileAccess: any StoredPDFAccessing
    let editSheet: (SongSheet) -> Void
    let deleteSheet: (SongSheet) -> Void

    var body: some View {
        List {
            SongSheetsSection(
                sheets: sheets,
                fileAccess: fileAccess,
                edit: editSheet,
                delete: deleteSheet
            )

            if !song.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("메모") {
                    Text(song.notes).textSelection(.enabled)
                }
            }
        }
    }
}

private struct SongSheetsSection: View {
    let sheets: [SongSheet]
    let fileAccess: any StoredPDFAccessing
    let edit: (SongSheet) -> Void
    let delete: (SongSheet) -> Void

    var body: some View {
        Section("악보") {
            if sheets.isEmpty {
                Label("연결된 악보가 없어요", systemImage: "doc.questionmark")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sheets, id: \.id) { sheet in
                    EditableSongSheetRow(
                        sheet: sheet,
                        fileAccess: fileAccess,
                        edit: { edit(sheet) },
                        delete: { delete(sheet) }
                    )
                }
            }
        }
    }
}

private struct EditableSongSheetRow: View {
    let sheet: SongSheet
    let fileAccess: any StoredPDFAccessing
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        if let document = sheet.document {
            NavigationLink {
                PDFViewerView(
                    document: document,
                    sheet: sheet,
                    fileAccess: fileAccess
                )
            } label: {
                SongSheetRow(sheet: sheet)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("삭제", systemImage: "trash", role: .destructive, action: delete)
                Button("수정", systemImage: "pencil", action: edit)
                    .tint(ArchiveTheme.tint)
            }
        } else {
            Label("원본 PDF 정보를 찾을 수 없어요", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SongMergeForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    let sourceSong: Song
    let merged: () -> Void
    @State private var viewModel: SongMergeViewModel

    init(sourceSong: Song, merged: @escaping () -> Void) {
        self.sourceSong = sourceSong
        self.merged = merged
        _viewModel = State(initialValue: SongMergeViewModel(sourceSong: sourceSong))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let targetSongs = viewModel.targetSongs(from: songs)

        Form {
            Section("현재 곡") {
                LabeledContent("병합할 곡", value: sourceSong.title)
                LabeledContent("연결된 악보", value: "\(sourceSong.sheets?.count ?? 0)개")
            }

            Section {
                if targetSongs.isEmpty {
                    Text("묶을 수 있는 다른 곡이 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("기존 곡", selection: $viewModel.targetSongID) {
                        Text("선택해 주세요").tag(nil as UUID?)
                        ForEach(targetSongs, id: \.id) { song in
                            Text(song.title).tag(song.id as UUID?)
                        }
                    }
                }
            } header: {
                Text("합칠 대상")
            } footer: {
                Text("현재 곡의 악보와 메모가 선택한 곡으로 이동하고 현재 곡 항목은 삭제됩니다.")
            }
        }
        .navigationTitle("동일한 곡 묶기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("묶기", action: merge)
                    .disabled(viewModel.targetSongID == nil)
            }
        }
        .alert(
            "곡을 묶지 못했어요",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private func merge() {
        if viewModel.merge(into: songs, in: modelContext) {
            dismiss()
            merged()
        }
    }
}

private struct SongEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: SongEditViewModel

    init(song: Song) {
        _viewModel = State(initialValue: SongEditViewModel(song: song))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("곡 정보") {
                TextField("곡 제목", text: $viewModel.title)
                TextField("메모", text: $viewModel.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .navigationTitle("곡 정보 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장", action: save)
            }
        }
        .alert(
            "저장하지 못했어요",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private func save() {
        if viewModel.save(in: modelContext) {
            dismiss()
        }
    }
}

private struct SongSheetEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: SongSheetEditViewModel

    init(sheet: SongSheet) {
        _viewModel = State(initialValue: SongSheetEditViewModel(sheet: sheet))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("악보 정보") {
                Picker("키", selection: $viewModel.musicalKey) {
                    Text("미지정").tag(nil as MusicalKey?)
                    ForEach(MusicalKey.allCases) { key in
                        Text(key.displayName).tag(key as MusicalKey?)
                    }
                }

                Stepper(
                    "시작 페이지 · \(viewModel.startPageNumber)",
                    value: $viewModel.startPageNumber,
                    in: 1...viewModel.pageCount
                )
                Stepper(
                    "마지막 페이지 · \(viewModel.endPageNumber)",
                    value: $viewModel.endPageNumber,
                    in: 1...viewModel.pageCount
                )
            }
        }
        .navigationTitle("악보 정보 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장", action: save)
            }
        }
        .alert(
            "저장하지 못했어요",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private func save() {
        if viewModel.save(in: modelContext) {
            dismiss()
        }
    }
}

private struct SongSheetRow: View {
    let sheet: SongSheet

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ArchiveTheme.tint)
                .frame(width: 40, height: 40)
                .background(ArchiveTheme.tint.opacity(0.12), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(sheet.song?.title ?? "악보")
                    .font(.headline)
                    .lineLimit(1)

                Text(sheetSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sheetSummary: String {
        let keyName = sheet.musicalKey?.displayName ?? "키 미지정"
        let pageDescription: String

        if sheet.startPageIndex == sheet.endPageIndex {
            pageDescription = "\(sheet.startPageIndex + 1)페이지"
        } else {
            pageDescription = "\(sheet.startPageIndex + 1)–\(sheet.endPageIndex + 1)페이지"
        }

        return "\(keyName) · \(pageDescription)"
    }
}
