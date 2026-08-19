import SwiftUI

struct LibraryView: View {
    @State private var mode: LibraryMode = .songs

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

            ScrollView {
                ArchiveEmptyState(
                    systemImage: mode.systemImage,
                    title: mode.emptyTitle,
                    message: mode.emptyMessage
                )
                .frame(maxWidth: 620)
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
        .background(ArchiveTheme.background)
        .navigationTitle("라이브러리")
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
}
