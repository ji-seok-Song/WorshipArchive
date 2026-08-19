import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        ScrollView {
            ArchiveEmptyState(
                systemImage: query.isEmpty ? "text.magnifyingglass" : "music.note",
                title: query.isEmpty ? "기억나는 단서를 입력해 보세요" : "검색 결과가 없어요",
                message: query.isEmpty
                    ? "곡 제목, 가사 한 구절, 키를 한 검색창에서 찾을 수 있어요."
                    : "‘\(query)’와 일치하는 악보가 아직 등록되지 않았어요."
            )
            .frame(maxWidth: 620)
            .padding()
        }
        .background(ArchiveTheme.background)
        .navigationTitle("검색")
        .searchable(text: $query, prompt: "제목, 가사, 키 검색")
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}
