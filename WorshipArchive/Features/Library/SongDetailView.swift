import SwiftData
import SwiftUI

struct SongDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let song: Song
    let fileAccess: any StoredPDFAccessing

    @State private var favoriteSaveErrorMessage: String?
    @State private var deleteRecordErrorMessage: String?
    @State private var showsPerformanceRecordForm = false
    @State private var recordPendingDeletion: PerformanceRecord?

    var body: some View {
        List {
            Section {
                LabeledContent("등록된 악보", value: "\(sortedSheets.count)개")
                LabeledContent("등록일", value: song.createdAt.formatted(date: .abbreviated, time: .omitted))
            }

            Section("악보") {
                if sortedSheets.isEmpty {
                    Label("연결된 악보가 없어요", systemImage: "doc.questionmark")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedSheets, id: \.id) { sheet in
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
                        } else {
                            Label("원본 PDF 정보를 찾을 수 없어요", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if sortedPerformanceRecords.isEmpty {
                    ContentUnavailableView(
                        "예배 기록이 없어요",
                        systemImage: "calendar.badge.plus",
                        description: Text("이 곡을 연주한 날짜와 예배 정보를 남겨 보세요.")
                    )
                } else {
                    ForEach(sortedPerformanceRecords, id: \.id) { record in
                        PerformanceRecordRow(record: record)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("삭제", systemImage: "trash", role: .destructive) {
                                    recordPendingDeletion = record
                                }
                            }
                            .contextMenu {
                                Button("기록 삭제", systemImage: "trash", role: .destructive) {
                                    recordPendingDeletion = record
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("예배 기록")
                    Spacer()
                    Button("기록 추가", systemImage: "plus") {
                        showsPerformanceRecordForm = true
                    }
                    .font(.subheadline)
                    .textCase(nil)
                }
            }

            if !song.lyricsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("검색 가능한 가사") {
                    Text(song.lyricsText)
                        .textSelection(.enabled)
                }
            }

            if !song.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("메모") {
                    Text(song.notes)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleFavorite) {
                    Label(
                        song.isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가",
                        systemImage: song.isFavorite ? "heart.fill" : "heart"
                    )
                }
                .tint(song.isFavorite ? ArchiveTheme.accent : ArchiveTheme.tint)
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
        .sheet(isPresented: $showsPerformanceRecordForm) {
            NavigationStack {
                PerformanceRecordFormView(song: song)
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
