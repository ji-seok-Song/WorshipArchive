import SwiftData
import SwiftUI

struct SongDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let song: Song
    let fileAccess: any StoredPDFAccessing

    @State private var favoriteSaveErrorMessage: String?
    @State private var deleteRecordErrorMessage: String?
    @State private var showsPerformanceRecordForm = false
    @State private var recordPendingDeletion: PerformanceRecord?
    @State private var showsSongEditor = false
    @State private var sheetBeingEdited: SongSheet?
    @State private var sheetPendingDeletion: SongSheet?
    @State private var showsSongDeleteConfirmation = false
    @State private var archiveEditErrorMessage: String?

    var body: some View {
        SongDetailContent(
            song: song,
            sheets: sortedSheets,
            records: sortedPerformanceRecords,
            fileAccess: fileAccess,
            editSheet: { sheetBeingEdited = $0 },
            deleteSheet: { sheetPendingDeletion = $0 },
            addRecord: { showsPerformanceRecordForm = true },
            deleteRecord: { recordPendingDeletion = $0 }
        )
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: toggleFavorite) {
                    Label(
                        song.isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가",
                        systemImage: song.isFavorite ? "heart.fill" : "heart"
                    )
                }
                .tint(song.isFavorite ? ArchiveTheme.accent : ArchiveTheme.tint)

                Menu {
                    Button("곡 정보 수정", systemImage: "pencil") {
                        showsSongEditor = true
                    }
                    Button("곡 삭제", systemImage: "trash", role: .destructive) {
                        showsSongDeleteConfirmation = true
                    }
                } label: {
                    Label("더 보기", systemImage: "ellipsis.circle")
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
            "예배 기록을 삭제하지 못했어요",
            isPresented: deleteRecordErrorIsPresented
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(deleteRecordErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .alert(
            "변경 사항을 저장하지 못했어요",
            isPresented: Binding(
                get: { archiveEditErrorMessage != nil },
                set: { if !$0 { archiveEditErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(archiveEditErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .confirmationDialog(
            "예배 기록을 삭제할까요?",
            isPresented: deleteConfirmationIsPresented,
            titleVisibility: .visible,
            presenting: recordPendingDeletion
        ) { record in
            Button("삭제", role: .destructive) {
                delete(record)
            }
            Button("취소", role: .cancel) {}
        } message: { record in
            Text("\(record.performedAt.formatted(date: .abbreviated, time: .omitted)) · \(record.serviceType)")
        }
        .confirmationDialog(
            "이 악보를 곡에서 삭제할까요?",
            isPresented: Binding(
                get: { sheetPendingDeletion != nil },
                set: { if !$0 { sheetPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: sheetPendingDeletion
        ) { sheet in
            Button("삭제", role: .destructive) { delete(sheet) }
            Button("취소", role: .cancel) {}
        } message: { sheet in
            Text("원본 PDF는 유지되고 \(sheet.startPageIndex + 1)~\(sheet.endPageIndex + 1)페이지 연결만 삭제됩니다.")
        }
        .confirmationDialog(
            "‘\(song.title)’을 삭제할까요?",
            isPresented: $showsSongDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("곡 삭제", role: .destructive, action: deleteSong)
            Button("취소", role: .cancel) {}
        } message: {
            Text("곡에 연결된 악보와 예배 기록이 함께 삭제됩니다. 원본 PDF는 유지됩니다.")
        }
        .sheet(isPresented: $showsPerformanceRecordForm) {
            NavigationStack {
                PerformanceRecordFormView(song: song)
            }
        }
        .sheet(isPresented: $showsSongEditor) {
            NavigationStack {
                SongEditForm(song: song)
            }
        }
        .sheet(item: $sheetBeingEdited) { sheet in
            NavigationStack {
                SongSheetEditForm(sheet: sheet)
            }
        }
    }

    private var sortedSheets: [SongSheet] {
        (song.sheets ?? []).sorted { lhs, rhs in
            let lhsName = lhs.document?.originalFileName ?? ""
            let rhsName = rhs.document?.originalFileName ?? ""
            if lhsName != rhsName {
                return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
            }
            if lhs.startPageIndex != rhs.startPageIndex {
                return lhs.startPageIndex < rhs.startPageIndex
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }


    private var sortedPerformanceRecords: [PerformanceRecord] {
        (song.performanceRecords ?? []).sorted { lhs, rhs in
            if lhs.performedAt != rhs.performedAt {
                return lhs.performedAt > rhs.performedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
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

    private var deleteRecordErrorIsPresented: Binding<Bool> {
        Binding(
            get: { deleteRecordErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteRecordErrorMessage = nil
                }
            }
        )
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { recordPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    recordPendingDeletion = nil
                }
            }
        )
    }

    private func toggleFavorite() {
        let previousValue = song.isFavorite
        song.isFavorite.toggle()

        do {
            try modelContext.save()
        } catch {
            song.isFavorite = previousValue
            favoriteSaveErrorMessage = error.localizedDescription
        }
    }

    private func delete(_ record: PerformanceRecord) {
        do {
            try PerformanceRecordPersistence.delete(record, in: modelContext)
            recordPendingDeletion = nil
        } catch {
            recordPendingDeletion = nil
            deleteRecordErrorMessage = error.localizedDescription
        }
    }

    private func delete(_ sheet: SongSheet) {
        do {
            try ArchiveLibraryEditing.deleteSheet(sheet, in: modelContext)
            sheetPendingDeletion = nil
        } catch {
            sheetPendingDeletion = nil
            archiveEditErrorMessage = error.localizedDescription
        }
    }

    private func deleteSong() {
        do {
            try ArchiveLibraryEditing.deleteSong(song, in: modelContext)
            dismiss()
        } catch {
            archiveEditErrorMessage = error.localizedDescription
        }
    }
}

private struct SongDetailContent: View {
    let song: Song
    let sheets: [SongSheet]
    let records: [PerformanceRecord]
    let fileAccess: any StoredPDFAccessing
    let editSheet: (SongSheet) -> Void
    let deleteSheet: (SongSheet) -> Void
    let addRecord: () -> Void
    let deleteRecord: (PerformanceRecord) -> Void

    var body: some View {
        List {
            Section {
                LabeledContent("등록된 악보", value: "\(sheets.count)개")
                LabeledContent(
                    "등록일",
                    value: song.createdAt.formatted(date: .abbreviated, time: .omitted)
                )
            }

            SongSheetsSection(
                sheets: sheets,
                fileAccess: fileAccess,
                edit: editSheet,
                delete: deleteSheet
            )

            PerformanceRecordsSection(
                records: records,
                add: addRecord,
                delete: deleteRecord
            )

            if !song.lyricsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("검색 가능한 가사") {
                    Text(song.lyricsText).textSelection(.enabled)
                }
            }

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
                SongSheetRow(sheet: sheet, document: document)
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

private struct PerformanceRecordsSection: View {
    let records: [PerformanceRecord]
    let add: () -> Void
    let delete: (PerformanceRecord) -> Void

    var body: some View {
        Section {
            if records.isEmpty {
                ContentUnavailableView(
                    "예배 기록이 없어요",
                    systemImage: "calendar.badge.plus",
                    description: Text("이 곡을 연주한 날짜와 예배 정보를 남겨 보세요.")
                )
            } else {
                ForEach(records, id: \.id) { record in
                    PerformanceRecordRow(record: record)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("삭제", systemImage: "trash", role: .destructive) {
                                delete(record)
                            }
                        }
                        .contextMenu {
                            Button("기록 삭제", systemImage: "trash", role: .destructive) {
                                delete(record)
                            }
                        }
                }
            }
        } header: {
            HStack {
                Text("예배 기록")
                Spacer()
                Button("기록 추가", systemImage: "plus", action: add)
                    .font(.subheadline)
                    .textCase(nil)
            }
        }
    }
}

private struct SongEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let song: Song
    @State private var title: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(song: Song) {
        self.song = song
        _title = State(initialValue: song.title)
        _notes = State(initialValue: song.notes)
    }

    var body: some View {
        Form {
            Section("곡 정보") {
                TextField("곡 제목", text: $title)
                TextField("메모", text: $notes, axis: .vertical)
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
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private func save() {
        do {
            try ArchiveLibraryEditing.updateSong(
                song,
                title: title,
                notes: notes,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SongSheetEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let sheet: SongSheet
    @State private var musicalKey: MusicalKey?
    @State private var startPageNumber: Int
    @State private var endPageNumber: Int
    @State private var errorMessage: String?

    init(sheet: SongSheet) {
        self.sheet = sheet
        _musicalKey = State(initialValue: sheet.musicalKey)
        _startPageNumber = State(initialValue: sheet.startPageIndex + 1)
        _endPageNumber = State(initialValue: sheet.endPageIndex + 1)
    }

    var body: some View {
        Form {
            Section("악보 정보") {
                Picker("키", selection: $musicalKey) {
                    Text("미지정").tag(nil as MusicalKey?)
                    ForEach(MusicalKey.allCases) { key in
                        Text(key.displayName).tag(key as MusicalKey?)
                    }
                }

                Stepper(
                    "시작 페이지 · \(startPageNumber)",
                    value: $startPageNumber,
                    in: 1...pageCount
                )
                Stepper(
                    "마지막 페이지 · \(endPageNumber)",
                    value: $endPageNumber,
                    in: 1...pageCount
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
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private var pageCount: Int {
        max(sheet.document?.pageCount ?? 1, 1)
    }

    private func save() {
        do {
            try ArchiveLibraryEditing.updateSheet(
                sheet,
                musicalKey: musicalKey,
                startPageNumber: startPageNumber,
                endPageNumber: endPageNumber,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PerformanceRecordRow: View {
    let record: PerformanceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(record.serviceType)
                    .font(.headline)

                Spacer()

                Text(record.performedAt, format: .dateTime.year().month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("쓸어 넘기거나 길게 눌러 삭제할 수 있습니다")
    }

    private var details: [String] {
        var values: [String] = []
        if let musicalKey = record.musicalKey {
            values.append(musicalKey.displayName)
        }
        if !record.leader.isEmpty {
            values.append("인도 \(record.leader)")
        }
        return values
    }
}

private struct SongSheetRow: View {
    let sheet: SongSheet
    let document: ArchiveDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ArchiveTheme.tint)
                .frame(width: 40, height: 40)
                .background(ArchiveTheme.tint.opacity(0.12), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.originalFileName)
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
