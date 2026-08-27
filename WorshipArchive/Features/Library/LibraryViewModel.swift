import Foundation
import Observation
import SwiftData

enum LibraryMode: String, CaseIterable, Identifiable {
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

@MainActor
@Observable
final class LibraryViewModel {
    var mode: LibraryMode = .songs
    var selectedKey: MusicalKey?
    var showsFavoritesOnly = false
    var favoriteSaveErrorMessage: String?
    var documentPendingDeletion: ArchiveDocument?
    var documentDeleteErrorMessage: String?

    var hasActiveSongFilter: Bool {
        selectedKey != nil || showsFavoritesOnly
    }

    func displayedSongs(from songs: [Song]) -> [Song] {
        SongSearchMatcher.filter(
            songs,
            using: SongSearchFilter(
                musicalKey: selectedKey,
                favoritesOnly: showsFavoritesOnly
            )
        )
    }

    func resetSongFilters() {
        selectedKey = nil
        showsFavoritesOnly = false
    }

    func filteredSongsEmptyMessage() -> String {
        switch (selectedKey, showsFavoritesOnly) {
        case (let key?, true):
            return "즐겨찾기 중 \(key.displayName) 키로 등록된 곡이 없어요."
        case (let key?, false):
            return "\(key.displayName) 키로 등록된 곡이 없어요."
        case (nil, true):
            return "자주 보는 곡의 하트를 눌러 이곳에 모아 보세요."
        case (nil, false):
            return "다른 키를 선택해 보세요."
        }
    }

    func keySummary(for song: Song) -> String {
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

    func toggleFavorite(for song: Song, in modelContext: ModelContext) {
        let previousValue = song.isFavorite
        song.isFavorite.toggle()

        do {
            try modelContext.save()
        } catch {
            song.isFavorite = previousValue
            favoriteSaveErrorMessage = error.localizedDescription
        }
    }

    func delete(
        _ document: ArchiveDocument,
        in modelContext: ModelContext,
        fileStore: any PDFFileStoring
    ) async {
        let storedFileName: String
        do {
            storedFileName = try ArchiveLibraryEditing.deleteDocument(
                document,
                in: modelContext
            )
            documentPendingDeletion = nil
        } catch {
            documentPendingDeletion = nil
            documentDeleteErrorMessage = error.localizedDescription
            return
        }

        do {
            try await fileStore.removeStoredFile(named: storedFileName)
        } catch PDFFileStoreError.storedFileMissing {
            // The requested final state is already satisfied.
        } catch {
            documentDeleteErrorMessage = "목록에서는 삭제했지만 기기 파일 정리가 남았습니다. 앱이 다음 정리 작업에서 다시 처리합니다."
        }
    }
}
